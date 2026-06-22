import Foundation

// MARK: - 타이머 단계(Phase)
// 포모도로 사이클의 현재 모드를 나타냅니다.
enum TimerPhase {
    case idle        // 대기 (아무것도 안 함)
    case focusing    // 집중 중
    case breakReady  // 집중 완료, 휴식 시작 대기
    case resting     // 휴식 중

    var isCountingDown: Bool {
        self == .focusing || self == .resting
    }
}

// MARK: - 타이머 설정
// 각 구간의 길이(분). 사용자가 설정에서 바꿀 수 있습니다.
struct TimerSettings: Codable, Equatable {
    var focusMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var sessionsUntilLongBreak: Int  // 몇 번의 집중마다 긴 휴식을 줄지

    static let `default` = TimerSettings(
        focusMinutes: 25,
        shortBreakMinutes: 5,
        longBreakMinutes: 15,
        sessionsUntilLongBreak: 4
    )

    // UserDefaults 저장용 키
    static let storageKey = "pomopet.timerSettings"

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func load() -> TimerSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(TimerSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }
}
