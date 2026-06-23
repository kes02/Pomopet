import Foundation
import SwiftUI
import SwiftData
import Combine
import AppKit

// MARK: - DayCell
// 히트맵(잔디) 한 칸. 특정 날짜의 세션 수를 담습니다.
struct DayCell: Identifiable {
    let key: Int          // yyyyMMdd
    let sessions: Int
    let isToday: Bool
    var id: Int { key }
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
    @Published private(set) var recentDays: [DayCell] = []  // 최근 35일 히트맵
    @Published private(set) var totalFocusSessions = 0   // 누적 통계(표시용)
    @Published private(set) var totalFocusMinutes = 0

    private var stats: AppStats?

    // MARK: 내부
    private var timer: Timer?
    private var modelContext: ModelContext?

    /// 하루 목표 세션 수 (최소 1)
    var dailyGoal: Int { max(1, settings.dailyGoalSessions) }

    init() {
        self.settings = TimerSettings.load()
    }

    // MARK: - 초기 설정
    func attach(context: ModelContext) {
        self.modelContext = context
        loadState()
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
        needsCharacter = false
        objectWillChange.send()
    }

    /// 캐릭터 이미지를 교체합니다 (스트릭/기록은 유지).
    func changeCharacter(_ image: NSImage) {
        CustomPetStore.save(image)
        needsCharacter = false
        objectWillChange.send()
    }

    // MARK: - 타이머 제어

    func startFocus() {
        phase = .focusing
        remainingSeconds = settings.focusMinutes * 60
        startTicking()
    }

    func startBreak() {
        phase = .resting
        remainingSeconds = settings.breakMinutes * 60
        startTicking()
    }

    func stop() {
        stopTicking()
        phase = .idle
        remainingSeconds = 0
    }

    func skipBreak() {
        stopTicking()
        phase = .idle
        remainingSeconds = 0
    }

    // MARK: - 타이머 틱

    private func startTicking() {
        stopTicking()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard remainingSeconds > 0 else {
            handlePhaseCompletion()
            return
        }
        remainingSeconds -= 1
    }

    // MARK: - 단계 완료 처리

    private func handlePhaseCompletion() {
        stopTicking()
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

        let key = Self.dayKey(for: Date())
        let descriptor = FetchDescriptor<DailyRecord>(
            predicate: #Predicate { $0.dayKey == key }
        )
        let record: DailyRecord
        if let existing = try? context.fetch(descriptor).first {
            record = existing
        } else {
            record = DailyRecord(dayKey: key, date: Calendar.current.startOfDay(for: Date()))
            context.insert(record)
        }
        record.sessions += 1
        record.minutes += settings.focusMinutes

        if let stats = stats {
            stats.totalFocusSessions += 1
            stats.totalFocusMinutes += settings.focusMinutes
        }

        saveContext()
        recomputeProgress()
    }

    // MARK: - 스트릭 / 진행 계산

    /// DailyRecord들로부터 오늘 활성화 여부, 현재/최고 스트릭, 히트맵을 다시 계산합니다.
    private func recomputeProgress() {
        guard let context = modelContext else { return }
        let records = (try? context.fetch(FetchDescriptor<DailyRecord>())) ?? []
        let goal = dailyGoal
        let today = Date()
        let todayKey = Self.dayKey(for: today)
        let cal = Calendar.current

        // 오늘 기록이 현재 목표를 충족하면 활성화를 켜둠(켜기만 함, 끄지 않음).
        // → 목표를 낮춰 충족되면 깨어나고, 목표를 올려도 이미 켜진 날은 유지됨.
        if let todayRecord = records.first(where: { $0.dayKey == todayKey }),
           todayRecord.sessions >= goal, !todayRecord.activated {
            todayRecord.activated = true
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

        // 최근 35일 히트맵 (과거 → 오늘 순)
        recentDays = (0..<35).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = Self.dayKey(for: d)
            let sessions = records.first(where: { $0.dayKey == key })?.sessions ?? 0
            return DayCell(key: key, sessions: sessions, isToday: key == todayKey)
        }

        // activated 업그레이드·bestStreak 갱신을 영구 저장
        saveContext()
    }

    private static func dayKey(for date: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    // MARK: - 설정 변경
    func updateSettings(_ newSettings: TimerSettings) {
        settings = newSettings
        newSettings.save()
        recomputeProgress()  // 일일 목표가 바뀌면 활성화/스트릭 재계산
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

    /// 메뉴바에 표시할 SF Symbol 이름 (활성=불꽃, 잠듦=달, 캐릭터 없음=점선 원)
    var menuBarSymbol: String {
        if needsCharacter { return "circle.dashed" }
        return isActiveToday ? "flame.fill" : "moon.zzz.fill"
    }
}
