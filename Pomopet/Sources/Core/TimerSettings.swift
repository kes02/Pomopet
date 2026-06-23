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
// 휴식은 짧은/긴 구분 없이 하나로 통합되어 있습니다.
struct TimerSettings: Codable, Equatable {
    var focusMinutes: Int
    var breakMinutes: Int            // 휴식 길이(짧은/긴 구분 없음)
    var dailyGoalSessions: Int       // 하루에 몇 세션을 채워야 "활성화"되는지

    static let `default` = TimerSettings(
        focusMinutes: 25,
        breakMinutes: 5,
        dailyGoalSessions: 1
    )

    init(focusMinutes: Int, breakMinutes: Int, dailyGoalSessions: Int) {
        self.focusMinutes = focusMinutes
        self.breakMinutes = breakMinutes
        self.dailyGoalSessions = dailyGoalSessions
    }

    // 예전 저장본(shortBreakMinutes 등)도 안전하게 읽기 위한 디코딩
    enum CodingKeys: String, CodingKey {
        case focusMinutes, breakMinutes, dailyGoalSessions, shortBreakMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 25
        breakMinutes = (try? c.decodeIfPresent(Int.self, forKey: .breakMinutes)) ?? nil
            ?? (try? c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes)) ?? nil
            ?? 5
        dailyGoalSessions = try c.decodeIfPresent(Int.self, forKey: .dailyGoalSessions) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(focusMinutes, forKey: .focusMinutes)
        try c.encode(breakMinutes, forKey: .breakMinutes)
        try c.encode(dailyGoalSessions, forKey: .dailyGoalSessions)
    }

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
