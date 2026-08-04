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
// 하루 목표는 두지 않습니다. 오늘 집중했으면 펫이 깨어나고 연속이 이어집니다.
// "몇 세션을 채워야 한다" 는 기준은 세션이라는 단위를 계속 의식하게 만들어 오히려 헷갈렸습니다.
struct TimerSettings: Codable, Equatable {
    var focusMinutes: Int
    var breakMinutes: Int            // 휴식 길이(짧은/긴 구분 없음)

    static let `default` = TimerSettings(
        focusMinutes: 25,
        breakMinutes: 5
    )

    init(focusMinutes: Int, breakMinutes: Int) {
        self.focusMinutes = focusMinutes
        self.breakMinutes = breakMinutes
    }

    // 예전 저장본(shortBreakMinutes·dailyGoalSessions)도 안전하게 읽기 위한 디코딩.
    // 하루 목표는 이제 쓰지 않으므로 읽고 버립니다.
    enum CodingKeys: String, CodingKey {
        case focusMinutes, breakMinutes, shortBreakMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.default
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? fallback.focusMinutes
        breakMinutes = (try? c.decodeIfPresent(Int.self, forKey: .breakMinutes)) ?? nil
            ?? (try? c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes)) ?? nil
            ?? fallback.breakMinutes
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(focusMinutes, forKey: .focusMinutes)
        try c.encode(breakMinutes, forKey: .breakMinutes)
    }

    // UserDefaults 저장용 키
    static let storageKey = "pomopet.timerSettings"

    func save() {
        DefaultsStore.save(self, forKey: Self.storageKey)
    }

    static func load() -> TimerSettings {
        DefaultsStore.load(TimerSettings.self, forKey: storageKey) ?? .default
    }
}
