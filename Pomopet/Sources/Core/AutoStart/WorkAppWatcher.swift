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
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
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
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target.bundleID,
                  self.shouldAsk()
            else { return }

            self.onSuggest?(target.name)
        }
    }

    private func shouldAsk() -> Bool {
        guard settings.enabled, let controller else { return false }
        guard controller.phase == .idle else { return false }        // 이미 돌고 있으면 끼어들지 않음
        guard !controller.needsCharacter else { return false }       // 캐릭터도 안 올린 상태면 아직 이르다

        if let snoozedUntil, snoozedUntil > Date() { return false }
        if let stopped = controller.lastManualStop,
           Date().timeIntervalSince(stopped) < Self.afterManualStop { return false }
        if settings.skipWhenGoalMet, controller.isActiveToday { return false }

        return true
    }
}
