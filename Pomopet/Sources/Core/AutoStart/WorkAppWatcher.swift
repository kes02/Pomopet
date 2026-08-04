import Foundation
import AppKit
import Combine

// MARK: - WorkAppWatcher
//
// 어떤 앱이 화면 앞으로 나왔는지 지켜보다가, 정해둔 작업 앱이면 "집중 시작할까요?" 하고 물어봅니다.
// NSWorkspace 알림만 쓰기 때문에 손쉬운 접근성 권한 같은 건 필요 없습니다.
//
// 이 클래스의 대부분은 "언제 묻지 말아야 하는가" 입니다. 물음이 잦으면 그 순간 성가신 기능이 됩니다.
//  * 이미 타이머가 돌고 있으면 묻지 않습니다 (집중·휴식 중에 끼어들지 않음)
//  * 앱을 스쳐 지나간 정도로는 묻지 않습니다 (앞으로 나온 채 dwellSeconds 만큼 머물러야 함)
//  * 방금 사용자가 직접 중단했으면 한동안 묻지 않습니다 (끈 걸 되살리지 않음)
//  * "나중에" 를 누르면 한동안 묻지 않습니다
//  * 오늘 목표를 이미 채웠으면 묻지 않습니다 (설정으로 끌 수 있음)

@MainActor
final class WorkAppWatcher: ObservableObject {

    @Published var settings: AutoStartSettings {
        didSet {
            settings.save()
            restart()
        }
    }

    weak var controller: PomopetController?

    /// 제안을 띄워야 할 때 불립니다(작업 앱 이름을 넘겨줍니다).
    var onSuggest: ((String) -> Void)?

    private var observer: NSObjectProtocol?
    private var dwellTask: Task<Void, Never>?
    private var recheckTimer: Timer?
    private var snoozedUntil: Date?

    /// 그날 "나중에" 를 누른 횟수. 계속 거절하면 그날은 그만 묻습니다.
    private var declinedToday = 0
    private var declinedDayKey = 0

    /// 사용자가 직접 중단한 뒤 이만큼은 묻지 않습니다.
    private static let afterManualStop: TimeInterval = 15 * 60
    /// "나중에" 를 누른 뒤 이만큼은 묻지 않습니다.
    private static let afterDismiss: TimeInterval = 30 * 60
    /// 하루에 이만큼 연달아 거절하면 그날은 더 묻지 않습니다.
    private static let maxDeclinesPerDay = 3
    /// 작업 앱에 계속 머무는 경우를 위해 이 주기로 다시 살펴봅니다.
    private static let recheckInterval: TimeInterval = 60

    init() {
        settings = AutoStartSettings.load()
    }

    // MARK: - 감시 시작/중지

    func start() {
        stop()
        guard settings.enabled, !settings.apps.isEmpty else { return }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            Task { @MainActor [weak self] in self?.appDidActivate(bundleID) }
        }

        // 알림은 "앱이 앞으로 나오는 순간" 에만 옵니다.
        // 그래서 이미 작업 앱을 켜둔 채로 Pomopet 이 시작되면(업데이트 직후가 그렇습니다)
        // 전환이 일어나지 않아 아무 일도 생기지 않습니다. 지금 맨 앞 앱을 한 번 확인합니다.
        appDidActivate(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)

        // 전환 알림만으로는 부족합니다.
        // 작업 앱에서 계속 일하는 중이면(세션이 끝난 뒤 이어서 작업하는 경우가 그렇습니다)
        // 전환이 일어나지 않아 영영 물어보지 않게 됩니다. 주기적으로 지금 상황을 다시 봅니다.
        let timer = Timer(timeInterval: Self.recheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.appDidActivate(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        recheckTimer = timer
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        recheckTimer?.invalidate()
        recheckTimer = nil
        dwellTask?.cancel()
        dwellTask = nil
    }

    private func restart() {
        if settings.enabled { start() } else { stop() }
    }

    /// "나중에" — 한동안 조용히 있습니다.
    ///
    /// 이제는 가만히 두면 시작되므로, 거절은 사용자가 분명하게 표현한 의사입니다.
    /// 그래서 몇 번 연달아 거절하면 그날은 아예 묻지 않습니다.
    func snooze() {
        rollOverDayIfNeeded()
        declinedToday += 1

        if declinedToday >= Self.maxDeclinesPerDay {
            snoozedUntil = Calendar.current.startOfDay(for: Date().addingTimeInterval(24 * 60 * 60))
        } else {
            snoozedUntil = Date().addingTimeInterval(Self.afterDismiss)
        }
    }

    /// 실제로 시작했으면 거절 횟수를 초기화합니다.
    func noteAccepted() {
        rollOverDayIfNeeded()
        declinedToday = 0
    }

    private func rollOverDayIfNeeded() {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let key = (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
        if key != declinedDayKey {
            declinedDayKey = key
            declinedToday = 0
        }
    }

    // MARK: - 판단

    private func appDidActivate(_ bundleID: String?) {
        // 작업 앱이 아닌 곳으로 갔으면 기다리던 것을 취소합니다.
        guard let bundleID, let target = settings.apps.first(where: { $0.bundleID == bundleID }) else {
            dwellTask?.cancel()
            dwellTask = nil
            return
        }
        guard shouldAsk() else { return }

        // 잠깐 들렀다 가는 것과 진짜 작업을 시작한 것을 구분합니다.
        dwellTask?.cancel()
        dwellTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let dwell = UInt64(max(1, settings.dwellSeconds)) * 1_000_000_000
            try? await Task.sleep(nanoseconds: dwell)
            guard !Task.isCancelled else { return }

            // 기다리는 동안 상황이 바뀌었을 수 있으니 다시 확인합니다.
            // 기다리는 동안 상황이 바뀌었을 수 있으니 다시 확인합니다.
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target.bundleID,
                  self.shouldAsk()
            else { return }

            self.onSuggest?(target.name)
        }
    }

    private func shouldAsk() -> Bool {
        guard settings.enabled, let controller else { return false }

        // 타이머가 돌고 있으면 끼어들지 않습니다.
        // 다만 breakReady(집중은 끝났고 휴식은 아직 안 누른 상태)는 돌고 있는 게 아니라
        // 대답을 기다리는 상태입니다. 휴식을 건너뛰고 곧장 이어서 작업하는 사람에게는
        // 이 상태가 무한정 유지되어 영영 물어보지 않는 꼴이 됩니다.
        guard controller.phase == .idle || controller.phase == .breakReady else { return false }
        guard !controller.needsCharacter else { return false }       // 캐릭터도 안 올린 상태면 아직 이르다

        if let snoozedUntil, snoozedUntil > Date() { return false }
        if let stopped = controller.lastManualStop,
           Date().timeIntervalSince(stopped) < Self.afterManualStop { return false }

        // "오늘 목표를 채웠으면 그만" 조건이 있었지만 뺐습니다.
        // 하루 목표가 없어진 지금은 오늘 한 번이라도 집중하면 곧바로 활성이 되어,
        // 첫 세션 이후로는 종일 물어보지 않는 꼴이 됩니다.
        // 하루에 몇 번씩 작업을 시작하는 게 정상이므로 계속 물어보고,
        // 성가심은 "나중에" 를 세 번 누르면 그날은 그만두는 쪽으로 막습니다.

        return true
    }
}
