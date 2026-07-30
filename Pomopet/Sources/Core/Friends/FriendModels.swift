import Foundation

// MARK: - 서버와 주고받는 값들
// pomopet-sync 서버(server/ 폴더)의 JSON 과 1:1 로 대응합니다.
// 오가는 건 집계된 숫자뿐입니다 — 몇 시에 뭘 했는지 같은 기록은 보내지 않습니다.

/// 친구 한 명의 오늘 상태.
struct FriendSummary: Codable, Identifiable, Equatable {
    let code: String
    let name: String
    let dayKey: Int
    let sessions: Int
    let minutes: Int
    let goal: Int
    let activated: Bool   // 오늘 펫이 깨어났는지
    let streak: Int
    let phase: String     // idle | focusing | breakReady | resting
    let petHash: String?
    let updatedAt: Double // epoch ms

    var id: String { code }

    /// 이름을 비워둔 친구는 코드로 대신 부릅니다.
    var displayName: String { name.isEmpty ? code : name }

    /// 지금 집중 중인지 (친구 목록에 "집중 중" 표시용)
    var isFocusing: Bool { phase == "focusing" }
}

/// 나를 찌른 기록.
struct NudgeEvent: Codable, Identifiable, Equatable {
    let from: String
    let name: String
    let at: Double

    var id: String { "\(from)-\(at)" }
    var displayName: String { name.isEmpty ? from : name }
}

struct HeartbeatRequest: Codable {
    let name: String
    let dayKey: Int
    let sessions: Int
    let minutes: Int
    let goal: Int
    let activated: Bool
    let streak: Int
    let phase: String
}

struct HeartbeatResponse: Codable {
    /// 서버에 저장된 "나" — 친구들이 보게 되는 바로 그 내용입니다.
    let me: FriendSummary?
    let friends: [FriendSummary]
    let nudges: [NudgeEvent]?
}

struct RegisterResponse: Codable {
    let userId: String
    let code: String
    let secret: String
}

struct AddFriendResponse: Codable {
    let friend: FriendSummary
}

struct PetResponse: Codable {
    let code: String
    let petHash: String?
    let pet: String
}

struct RotateCodeResponse: Codable {
    let code: String
}

// MARK: - 타이머 단계 → 서버 표기
extension TimerPhase {
    var wireName: String {
        switch self {
        case .idle: return "idle"
        case .focusing: return "focusing"
        case .breakReady: return "breakReady"
        case .resting: return "resting"
        }
    }
}
