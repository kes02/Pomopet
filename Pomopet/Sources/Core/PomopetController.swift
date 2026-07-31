import Foundation
import SwiftUI
import SwiftData
import Combine
import AppKit

// MARK: - DayStat
// 특정 날짜의 활동 기록(세션 수 + 집중 시간). 히트맵 월 달력 조회용.
struct DayStat {
    let sessions: Int
    let minutes: Int
}

// MARK: - PomopetController
// 앱의 두뇌. 타이머 진행, 세션 완료 기록, 일일 활성화/스트릭 계산을 담당합니다.
@MainActor
final class PomopetController: ObservableObject {

    // MARK: 발행되는 상태 (뷰가 자동으로 반응)
    @Published private(set) var phase: TimerPhase = .idle
    @Published private(set) var remainingSeconds: Int = 0
    @Published var settings: TimerSettings

    // 캐릭터 / 리텐션 상태
    @Published private(set) var needsCharacter = false   // 아직 캐릭터를 안 올린 상태
    @Published private(set) var todaySessions = 0        // 오늘 완료한 세션 수
    @Published private(set) var currentStreak = 0        // 현재 연속일
    @Published private(set) var bestStreak = 0           // 역대 최고 연속일
    @Published private(set) var isActiveToday = false    // 오늘 목표 달성(=활성화)
    @Published private(set) var dayStats: [Int: DayStat] = [:]  // 날짜키(yyyyMMdd) → 그날 기록 (히트맵용)
    @Published private(set) var totalFocusSessions = 0   // 누적 통계(표시용)
    @Published private(set) var totalFocusMinutes = 0

    private var stats: AppStats?

    // MARK: 내부
    private var timer: Timer?
    private var modelContext: ModelContext?

    /// 진행 중인 세션. 앱이 꺼져도 이어서 진행하려고 남겨둡니다.
    ///
    /// 남은 초를 세는 대신 "언제 끝나는지"(endsAt)를 저장합니다. 1초씩 빼는 방식은
    /// 절전·앱 정지 구간에서 실제 시각과 어긋나기 때문입니다.
    private struct RunningSession: Codable {
        var phase: String        // focusing | resting
        var startedAt: Date
        var endsAt: Date
        var lastSeen: Date       // 앱이 마지막으로 살아 있던 시각
    }

    private var running: RunningSession?
    private static let runningKey = "pomopet.runningSession"

    /// 앱이 이만큼 안에 다시 켜지면 진행 중이던 세션을 이어서 갑니다(업데이트·재시작).
    /// 그보다 오래 꺼져 있었다면 자리에 없었다고 보고 지켜본 만큼만 인정합니다.
    private static let resumeGrace: TimeInterval = 3 * 60

    /// 오늘 날짜 키(yyyyMMdd). 친구 연동에서 사용.
    var todayDayKey: Int { Self.dayKey(for: Date()) }

    /// 오늘 누적 집중 시간(분). 지금 진행 중인 세션의 흘러간 시간도 함께 셉니다.
    ///
    /// 기록에는 세션이 끝나야 더해지는데, 그것만 보면 30분째 집중하는 중에도 "오늘 0분"
    /// 으로 보입니다. 진행 중인 만큼을 얹어 실제로 한 만큼이 보이게 합니다.
    /// (세션이 끝나면 그 시간이 기록으로 옮겨가고 running 이 비워지므로 중복되지 않습니다)
    var todayMinutes: Int {
        (dayStats[todayDayKey]?.minutes ?? 0) + liveFocusMinutes
    }

    /// 지금 돌고 있는 집중 세션에서 흘러간 시간(분).
    private var liveFocusMinutes: Int {
        guard phase == .focusing, let running else { return 0 }
        return max(0, Int(Date().timeIntervalSince(running.startedAt)) / 60)
    }

    /// 펫이 깨어 있는지.
    /// 오늘 이미 집중했거나, 지금 집중하는 중이면 깨어 있습니다 —
    /// 공부하는 동안 펫이 자고 있으면 앞뒤가 안 맞습니다.
    var isPetAwake: Bool {
        isActiveToday || phase == .focusing
    }

    /// 진행 상황이나 타이머 단계가 바뀌면 알립니다.
    /// 친구 연동이 켜져 있으면 이 신호로 서버에 즉시 반영합니다(꺼져 있으면 아무 일도 일어나지 않음).
    var onProgressChanged: (() -> Void)?

    /// 사용자가 직접 타이머를 멈춘 시각.
    /// 작업 시작 감지가 방금 끈 타이머를 곧바로 다시 권하지 않도록 하는 데 씁니다.
    private(set) var lastManualStop: Date?

    init() {
        self.settings = TimerSettings.load()
    }

    // MARK: - 초기 설정
    func attach(context: ModelContext) {
        self.modelContext = context
        loadState()
        restoreRunningSession()
    }

    /// 앱이 꺼지기 전 돌고 있던 세션을 복구합니다.
    private func restoreRunningSession() {
        guard let data = UserDefaults.standard.data(forKey: Self.runningKey),
              let saved = try? JSONDecoder().decode(RunningSession.self, from: data)
        else { return }

        let now = Date()

        // 잠깐 꺼졌다 켜진 경우(업데이트·재시작)만 이어서 진행합니다.
        if now.timeIntervalSince(saved.lastSeen) <= Self.resumeGrace, now < saved.endsAt {
            running = saved
            phase = saved.phase == "focusing" ? .focusing : .resting
            remainingSeconds = max(0, Int(saved.endsAt.timeIntervalSince(now)))
            startTicking()
            return
        }

        // 오래 꺼져 있었으면 완주로 쳐주지 않습니다. 앱이 지켜본 시간만 인정합니다.
        if saved.phase == "focusing" {
            let observed = Int(saved.lastSeen.timeIntervalSince(saved.startedAt)) / 60
            recordPartialFocus(minutes: observed >= Self.minimumCreditedMinutes ? observed : 0)
        }
        clearRunningSession()
    }

    private func saveRunningSession() {
        guard let running, let data = try? JSONEncoder().encode(running) else { return }
        UserDefaults.standard.set(data, forKey: Self.runningKey)
    }

    private func clearRunningSession() {
        running = nil
        UserDefaults.standard.removeObject(forKey: Self.runningKey)
    }

    private func loadState() {
        guard let context = modelContext else { return }

        // 통계 로드 (없으면 생성)
        let statsDescriptor = FetchDescriptor<AppStats>()
        if let existing = try? context.fetch(statsDescriptor).first {
            self.stats = existing
        } else {
            let newStats = AppStats()
            context.insert(newStats)
            self.stats = newStats
        }

        needsCharacter = !CustomPetStore.hasImage
        recomputeProgress()
        saveContext()
    }

    // MARK: - 캐릭터

    /// 첫 실행 등에서 키울 캐릭터 이미지를 등록합니다.
    func setCharacter(_ image: NSImage) {
        CustomPetStore.save(image)
        PetMenuBarIcon.invalidate()   // 메뉴바 아이콘을 새 캐릭터로 다시 그리도록
        needsCharacter = false
        objectWillChange.send()
    }

    /// 캐릭터 이미지를 교체합니다 (스트릭/기록은 유지).
    func changeCharacter(_ image: NSImage) {
        CustomPetStore.save(image)
        PetMenuBarIcon.invalidate()
        needsCharacter = false
        objectWillChange.send()
    }

    // MARK: - 타이머 제어

    func startFocus() {
        beginSession(named: "focusing", minutes: settings.focusMinutes, phase: .focusing)
    }

    func startBreak() {
        beginSession(named: "resting", minutes: settings.breakMinutes, phase: .resting)
    }

    private func beginSession(named name: String, minutes: Int, phase newPhase: TimerPhase) {
        let now = Date()
        running = RunningSession(
            phase: name,
            startedAt: now,
            endsAt: now.addingTimeInterval(TimeInterval(minutes * 60)),
            lastSeen: now
        )
        saveRunningSession()

        phase = newPhase
        remainingSeconds = minutes * 60
        startTicking()
        onProgressChanged?()
    }

    /// 사용자가 직접 멈춤. 지금까지 집중한 시간은 누적 기록에 남깁니다.
    func stop() {
        halt(idleMinutes: 0)
    }

    /// 자리를 비워 자동으로 멈춤. 비운 시간만큼은 빼고 기록합니다.
    func stopAfterAway(idleMinutes: Int) {
        halt(idleMinutes: idleMinutes)
    }

    func skipBreak() {
        halt(idleMinutes: 0)
    }

    /// 타이머를 멈추고, 집중 중이었다면 흘러간 시간을 기록에 반영합니다.
    ///
    /// 세션 수는 올리지 않습니다. 세션은 하루 목표·스트릭의 단위라, 완주하지 않은 것을
    /// 한 세션으로 치면 목표가 헐거워집니다. 반면 집중한 시간 자체는 실제로 한 일이라
    /// 누적 시간과 그날 기록에는 남기는 게 맞습니다.
    private func halt(idleMinutes: Int) {
        clearRunningSession()

        if phase == .focusing {
            recordPartialFocus(minutes: Self.creditedMinutes(
                focusMinutes: settings.focusMinutes,
                remainingSeconds: remainingSeconds,
                idleMinutes: idleMinutes
            ))
        }

        stopTicking()
        phase = .idle
        remainingSeconds = 0
        lastManualStop = Date()
        onProgressChanged?()
    }

    /// 이보다 짧게 집중하고 멈추면 기록하지 않습니다.
    /// 집중했다고 보기 어렵고, 켰다 껐다 하며 시간을 부풀리는 것도 막습니다.
    static let minimumCreditedMinutes = 5

    /// 멈춘 시점까지 기록에 반영할 집중 시간(분). 기준에 못 미치면 0.
    ///
    /// 자리를 비운 시간(idleMinutes)은 빼고 셉니다 — 비운 시간이 집중 시간으로
    /// 둔갑하면 기록이 부풀기 때문입니다.
    static func creditedMinutes(focusMinutes: Int, remainingSeconds: Int, idleMinutes: Int) -> Int {
        let elapsed = max(0, focusMinutes * 60 - remainingSeconds) / 60
        let credited = max(0, elapsed - idleMinutes)
        return credited >= minimumCreditedMinutes ? credited : 0
    }

    /// 완주하지 못한 집중 시간을 그날 기록과 누적 통계에 더합니다.
    private func recordPartialFocus(minutes: Int) {
        guard minutes > 0, let context = modelContext else { return }

        let record = todayRecord(in: context)
        record.minutes += minutes
        stats?.totalFocusMinutes += minutes

        saveContext()
        recomputeProgress()
    }

    // MARK: - 타이머 틱

    private func startTicking() {
        stopTicking()

        // .common 모드로 직접 등록합니다.
        //  * scheduledTimer 는 앱이 막 시작해 run loop 가 아직 돌기 전이면 등록이 헛돕니다
        //    (업데이트 후 진행 중이던 세션을 이어받을 때가 그 경우입니다)
        //  * 기본 모드로만 걸면 메뉴바 팝오버를 여는 동안 run loop 가 추적 모드로 바뀌어
        //    카운트다운이 멈춥니다
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    /// 남은 시간은 1초씩 빼는 대신 끝나는 시각에서 계산합니다.
    /// 절전이나 앱 정지로 틱이 밀려도 실제 시각과 어긋나지 않습니다.
    private func tick() {
        guard let running else {
            handlePhaseCompletion()
            return
        }

        let remaining = Int(running.endsAt.timeIntervalSinceNow.rounded(.up))
        guard remaining > 0 else {
            handlePhaseCompletion()
            return
        }
        remainingSeconds = remaining

        // 10초마다 "여기까지 살아 있었다" 를 남깁니다. 갑자기 꺼져도 그 지점까지는 인정됩니다.
        if Int(Date().timeIntervalSince(self.running?.lastSeen ?? Date())) >= 10 {
            self.running?.lastSeen = Date()
            saveRunningSession()
        }
    }

    // MARK: - 단계 완료 처리

    private func handlePhaseCompletion() {
        stopTicking()
        clearRunningSession()
        switch phase {
        case .focusing:
            completeFocusSession()
            phase = .breakReady
        case .resting:
            phase = .idle
        default:
            phase = .idle
        }
        remainingSeconds = 0
    }

    /// 집중 세션이 정상 완료되었을 때: 오늘 기록 + 통계 + 스트릭 갱신
    private func completeFocusSession() {
        guard let context = modelContext else { return }

        let record = todayRecord(in: context)
        record.sessions += 1
        record.minutes += settings.focusMinutes

        if let stats = stats {
            stats.totalFocusSessions += 1
            stats.totalFocusMinutes += settings.focusMinutes
        }

        saveContext()
        recomputeProgress()
    }

    /// 오늘 기록을 가져오고, 없으면 만듭니다.
    private func todayRecord(in context: ModelContext) -> DailyRecord {
        let key = Self.dayKey(for: Date())
        let descriptor = FetchDescriptor<DailyRecord>(
            predicate: #Predicate { $0.dayKey == key }
        )
        if let existing = try? context.fetch(descriptor).first { return existing }

        let record = DailyRecord(dayKey: key, date: Calendar.current.startOfDay(for: Date()))
        context.insert(record)
        return record
    }

    // MARK: - 스트릭 / 진행 계산

    /// DailyRecord들로부터 오늘 활성화 여부, 현재/최고 스트릭, 히트맵을 다시 계산합니다.
    private func recomputeProgress() {
        guard let context = modelContext else { return }
        let records = (try? context.fetch(FetchDescriptor<DailyRecord>())) ?? []
        let today = Date()
        let todayKey = Self.dayKey(for: today)
        let cal = Calendar.current

        // 집중한 날은 활성으로 표시합니다(켜기만 하고 끄지 않음).
        // 지난 날도 함께 맞춥니다 — 예전 "하루 목표" 기준으로 미달 처리됐던 날들이
        // 지금 기준(집중했으면 활성)으로는 활성이어야 하므로, 한 번 올려두고 갑니다.
        for record in records where record.minutes > 0 && !record.activated {
            record.activated = true
        }

        // 활성화 여부는 저장된 activated 플래그로 판단(목표 변경에 영향받지 않음).
        let metDays = Set(records.filter { $0.activated }.map { $0.dayKey })

        todaySessions = records.first(where: { $0.dayKey == todayKey })?.sessions ?? 0
        isActiveToday = metDays.contains(todayKey)

        // 스트릭: 오늘(미달이면 어제)부터 하루씩 뒤로 가며 연속 달성일 카운트
        var streak = 0
        var cursor = isActiveToday ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
        while metDays.contains(Self.dayKey(for: cursor)) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        currentStreak = streak

        if let stats = stats {
            if streak > stats.bestStreak { stats.bestStreak = streak }
            bestStreak = stats.bestStreak
            totalFocusSessions = stats.totalFocusSessions
            totalFocusMinutes = stats.totalFocusMinutes
        }

        // 히트맵용: 모든 날짜의 세션/집중시간 기록을 날짜키로 조회 가능하게
        var map: [Int: DayStat] = [:]
        for r in records {
            map[r.dayKey] = DayStat(sessions: r.sessions, minutes: r.minutes)
        }
        dayStats = map

        // activated 업그레이드·bestStreak 갱신을 영구 저장
        saveContext()

        onProgressChanged?()
    }

    private static func dayKey(for date: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    // MARK: - 설정 변경
    func updateSettings(_ newSettings: TimerSettings) {
        settings = newSettings
        newSettings.save()
    }

    // MARK: - 저장
    private func saveContext() {
        try? modelContext?.save()
    }

    // MARK: - 표시용 헬퍼

    /// "25:00" 형태의 남은 시간 문자열
    var timeString: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// 메뉴바 유휴 상태의 펫 표정. 오늘 집중 기록이 없으면 잠든 얼굴.
    /// (집중·휴식 진행 중엔 표정 대신 시간을 보여주므로 MenuBarLabel에서 이 값을 쓰지 않음)
    var menuBarFace: String {
        if needsCharacter { return "(·_·)" }
        return todayMinutes > 0 ? "(•ᴗ•)" : "(-.-)"
    }
}
