import Foundation

// MARK: - 서버 통신
// pomopet-sync 서버로 보내는 HTTP 호출만 담당합니다. 상태는 갖지 않습니다.

enum FriendClientError: LocalizedError, Equatable {
    case notConnected            // 아직 연동을 안 켰음
    case codeNotFound            // 그런 코드를 가진 사람이 없음
    case alreadyFriend
    case cannotAddSelf
    case notAFriend
    case tooSoon(retryAfter: TimeInterval)
    case dailyLimit
    case server(status: Int, code: String?)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return appString("친구 연동이 켜져 있지 않아요")
        case .codeNotFound: return appString("그런 코드를 가진 사람이 없어요")
        case .alreadyFriend: return appString("이미 친구예요")
        case .cannotAddSelf: return appString("내 코드는 추가할 수 없어요")
        case .notAFriend: return appString("친구가 아니에요")
        case .tooSoon: return appString("방금 찔렀어요. 조금 뒤에 다시 해주세요")
        case .dailyLimit: return appString("오늘은 그만 찌르는 게 좋겠어요")
        case .server: return appString("서버가 응답하지 않아요")
        case .network: return appString("인터넷에 연결되어 있는지 확인해주세요")
        }
    }
}

struct FriendClient {
    var baseURL: URL

    /// 기본 서버. 직접 띄운 서버를 쓰려면 설정에서 주소를 바꾸면 됩니다.
    static let defaultBaseURL = URL(string: "https://pomopet-sync.kes02.workers.dev")!

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // MARK: 엔드포인트

    func register(name: String) async throws -> RegisterResponse {
        try await send("POST", "/v1/register", body: ["name": name])
    }

    func heartbeat(secret: String, _ payload: HeartbeatRequest) async throws -> HeartbeatResponse {
        try await send("POST", "/v1/heartbeat", secret: secret, encodable: payload)
    }

    func addFriend(secret: String, code: String) async throws -> FriendSummary {
        let response: AddFriendResponse = try await send(
            "POST", "/v1/friends", secret: secret, body: ["code": code]
        )
        return response.friend
    }

    func removeFriend(secret: String, code: String) async throws {
        let _: Empty = try await send("DELETE", "/v1/friends/\(code)", secret: secret)
    }

    func nudge(secret: String, code: String) async throws {
        let _: Empty = try await send("POST", "/v1/nudge", secret: secret, body: ["code": code])
    }

    func uploadPet(secret: String, base64 pet: String, hash: String) async throws {
        let _: Empty = try await send(
            "PUT", "/v1/pet", secret: secret, body: ["pet": pet, "petHash": hash]
        )
    }

    func fetchPet(secret: String, code: String) async throws -> PetResponse {
        try await send("GET", "/v1/pet/\(code)", secret: secret)
    }

    func rotateCode(secret: String) async throws -> String {
        let response: RotateCodeResponse = try await send("POST", "/v1/code/rotate", secret: secret)
        return response.code
    }

    func deleteAccount(secret: String) async throws {
        let _: Empty = try await send("DELETE", "/v1/me", secret: secret)
    }

    // MARK: 전송

    private struct Empty: Codable {}

    private func send<T: Decodable>(
        _ method: String, _ path: String, secret: String? = nil,
        body: [String: String]? = nil
    ) async throws -> T {
        try await perform(method, path, secret: secret, data: body.flatMap { try? JSONEncoder().encode($0) })
    }

    private func send<T: Decodable, B: Encodable>(
        _ method: String, _ path: String, secret: String? = nil, encodable: B
    ) async throws -> T {
        try await perform(method, path, secret: secret, data: try? JSONEncoder().encode(encodable))
    }

    private func perform<T: Decodable>(
        _ method: String, _ path: String, secret: String?, data: Data?
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        if let secret { request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization") }
        if let data {
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let payload: Data
        let response: URLResponse
        do {
            (payload, response) = try await Self.session.data(for: request)
        } catch {
            throw FriendClientError.network(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Self.mapError(status: status, payload: payload)
        }

        // 본문이 필요 없는 응답(Empty)은 굳이 파싱하지 않습니다.
        if T.self == Empty.self, let empty = Empty() as? T { return empty }
        guard let decoded = try? JSONDecoder().decode(T.self, from: payload) else {
            throw FriendClientError.server(status: status, code: "decode_failed")
        }
        return decoded
    }

    /// 서버가 내려준 error 코드를 사람이 읽을 수 있는 실패로 바꿉니다.
    private static func mapError(status: Int, payload: Data) -> FriendClientError {
        struct ErrorBody: Decodable {
            let error: String?
            let retryAfterMs: Double?
        }
        let body = try? JSONDecoder().decode(ErrorBody.self, from: payload)

        switch body?.error {
        case "code_not_found": return .codeNotFound
        case "cannot_add_self": return .cannotAddSelf
        case "not_a_friend": return .notAFriend
        case "nudge_too_soon": return .tooSoon(retryAfter: (body?.retryAfterMs ?? 0) / 1000)
        case "nudge_daily_limit": return .dailyLimit
        default: return .server(status: status, code: body?.error)
        }
    }
}
