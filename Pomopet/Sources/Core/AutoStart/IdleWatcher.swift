import Foundation
import AppKit
import CoreGraphics

// MARK: - IdleWatcher
//
// 집중 중인데 한참 아무 입력이 없으면 "자리 비우셨나요?" 하고 물어봅니다.
//
// 이게 없으면 자리를 비운 시간까지 집중 시간으로 쌓입니다. 작업 앱을 켜면 자동으로 권하게 된 뒤로는
// 더 그렇습니다 — 켜두고 나갔다가 25분이 통째로 기록되는 일이 생깁니다.
//
// 고정 주기로 훑지 않습니다. 마지막 입력 이후 시간을 알 수 있으니, 기준선(5분)까지 남은 만큼만
// 자고 일어나면 됩니다. 정확도는 초 단위인데 깨어나는 횟수는 4분 주기보다도 적습니다.

@MainActor
final class IdleWatcher {

    /// 이만큼 조용하면 물어봅니다.
    static let threshold: TimeInterval = 5 * 60

    /// 집중 중이 아닐 때 다시 확인하기까지.
    private static let idleTick: TimeInterval = 30

    weak var controller: PomopetController?

    /// 자리를 비운 것 같을 때 불립니다(몇 분째 조용한지 넘겨줍니다).
    var onAway: ((Int) -> Void)?

    private var loop: Task<Void, Never>?
    /// 이번 집중 세션에서 이미 물어봤는지 — 한 세션에 한 번만 묻습니다.
    private var askedThisSession = false

    func start() {
        stop()
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let wait = self.step()
                try? await Task.sleep(nanoseconds: UInt64(max(5, wait) * 1_000_000_000))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// 사용자가 대답했거나 세션이 끝났을 때 — 다음 세션에서 다시 물어볼 수 있게 합니다.
    func resetForNewSession() {
        askedThisSession = false
    }

    /// 지금 상황을 보고, 다음에 몇 초 뒤에 깨어날지 돌려줍니다.
    private func step() -> TimeInterval {
        guard let controller, controller.phase == .focusing else {
            askedThisSession = false
            return Self.idleTick
        }
        guard !askedThisSession else { return Self.idleTick }

        let idle = Self.systemIdleSeconds()
        if idle >= Self.threshold {
            askedThisSession = true
            onAway?(Int(idle / 60))
            return Self.idleTick
        }

        // 기준선까지 남은 만큼만 자고 일어납니다.
        return Self.threshold - idle
    }

    /// 마지막 키보드·마우스 입력 이후 지난 시간(초). 권한이 필요 없습니다.
    ///
    /// "아무 입력" 을 뜻하는 값(~0)은 Swift 에서 CGEventType 으로 만들 수 없어서,
    /// 실제 입력 종류들을 각각 물어보고 그중 가장 최근 것을 씁니다.
    private static func systemIdleSeconds() -> TimeInterval {
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged,
            .keyDown, .keyUp, .flagsChanged, .scrollWheel,
        ]
        return types
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }
}
