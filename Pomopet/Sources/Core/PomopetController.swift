import Foundation
import SwiftUI
import SwiftData
import Combine

// MARK: - PomopetController
// 앱의 두뇌. 타이머 진행, 세션 완료 처리, 진화/부화 로직을 담당합니다.
// @MainActor: UI 갱신은 메인 스레드에서 이루어져야 하므로 지정.
// ObservableObject: SwiftUI 뷰가 이 객체의 변화를 구독할 수 있게 합니다.
@MainActor
final class PomopetController: ObservableObject {

    // MARK: 발행되는 상태 (뷰가 자동으로 반응)
    @Published private(set) var phase: TimerPhase = .idle
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var completedFocusInCycle: Int = 0  // 긴 휴식 계산용
    @Published var settings: TimerSettings

    // 현재 생물 / 통계 (SwiftData에서 로드)
    @Published private(set) var currentCreature: Creature?
    @Published private(set) var stats: AppStats?

    // MARK: 내부
    private var timer: Timer?
    private var modelContext: ModelContext?

    init() {
        self.settings = TimerSettings.load()
    }

    // MARK: - 초기 설정
    // 앱 시작 시 SwiftData 컨텍스트를 연결하고 현재 상태를 불러옵니다.
    func attach(context: ModelContext) {
        self.modelContext = context
        loadOrCreateState()
    }

    private func loadOrCreateState() {
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

        // 아직 완성되지 않은 현재 생물 로드 (없으면 새 알 부화)
        let creatureDescriptor = FetchDescriptor<Creature>(
            predicate: #Predicate { $0.isCompleted == false }
        )
        if let existing = try? context.fetch(creatureDescriptor).first {
            self.currentCreature = existing
        } else {
            hatchNewCreature()
        }

        saveContext()
    }

    // MARK: - 타이머 제어

    /// 집중 세션 시작
    func startFocus() {
        phase = .focusing
        remainingSeconds = settings.focusMinutes * 60
        startTicking()
    }

    /// 휴식 시작 (짧은/긴 휴식 자동 판단)
    func startBreak() {
        let isLongBreak = completedFocusInCycle > 0
            && completedFocusInCycle % settings.sessionsUntilLongBreak == 0
        let minutes = isLongBreak ? settings.longBreakMinutes : settings.shortBreakMinutes
        phase = .resting
        remainingSeconds = minutes * 60
        startTicking()
    }

    /// 현재 진행 중인 것을 중단하고 대기 상태로.
    /// 집중 중 중단 시 진화 게이지는 증가하지 않습니다 (생물은 죽지 않음).
    func stop() {
        stopTicking()
        phase = .idle
        remainingSeconds = 0
    }

    /// 휴식 건너뛰기
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

    /// 집중 세션이 정상 완료되었을 때: 게이지 증가 + 통계 + 진화/부화 검사
    private func completeFocusSession() {
        completedFocusInCycle += 1

        // 통계 갱신
        if let stats = stats {
            stats.totalFocusSessions += 1
            stats.totalFocusMinutes += settings.focusMinutes
        }

        // 현재 생물 성장
        guard let creature = currentCreature else { return }
        let previousStage = creature.stage
        creature.sessionsCompleted += 1
        let newStage = creature.stage

        // 완전체 도달 → 도감 등록 후 새 알 부화
        if newStage == .adult && previousStage != .adult {
            completeCreature(creature)
        }

        saveContext()
    }

    /// 생물을 완성 처리하고 도감에 기록한 뒤 새 생물을 부화시킵니다.
    private func completeCreature(_ creature: Creature) {
        guard let context = modelContext else { return }
        creature.isCompleted = true
        creature.completedAt = Date()

        let entry = CollectionEntry(speciesId: creature.speciesId, completedAt: Date())
        context.insert(entry)

        if let stats = stats {
            stats.creaturesCompleted += 1
        }

        hatchNewCreature()
    }

    /// 새 알을 부화시킵니다 (무작위 종).
    private func hatchNewCreature() {
        guard let context = modelContext else { return }
        let newCreature = Creature(speciesId: SpeciesCatalog.randomSpeciesId())
        context.insert(newCreature)
        self.currentCreature = newCreature
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

    /// 메뉴바에 표시할 SF Symbol 이름
    var menuBarSymbol: String {
        guard let creature = currentCreature else { return "circle.dashed" }
        return creature.species.symbol(for: creature.stage)
    }
}
