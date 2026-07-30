import Foundation

// MARK: - 친구 연동 신원
// 서버에는 계정이 없습니다. 최초 1회 발급받은 secret 이 곧 나 자신이고, 코드는 친구에게 알려주는 이름표입니다.

struct FriendIdentity: Codable, Equatable {
    var code: String
    var secret: String
}

/// secret 을 파일로 보관합니다.
///
/// Keychain 이 아니라 파일인 이유: 이 앱은 정식 서명이 아니라 빌드·업데이트마다 서명이 달라집니다.
/// 그러면 Keychain 이 매번 "접근을 허용할까요?" 를 묻게 되어 업데이트할 때마다 성가십니다.
/// 이 secret 으로 할 수 있는 일은 내 세션 수를 올리고 친구 목록을 보는 정도라, 같은 사용자 권한으로
/// 어차피 읽을 수 있는 SwiftData 기록·UserDefaults 와 위험도가 다르지 않습니다. 대신 파일 권한을 600 으로 둡니다.
enum FriendIdentityStore {
    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pomopet", isDirectory: true)
    }

    private static var fileURL: URL {
        directory.appendingPathComponent("friend-identity.json")
    }

    static func load() -> FriendIdentity? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(FriendIdentity.self, from: data)
    }

    static func save(_ identity: FriendIdentity) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(identity) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        // 소유자만 읽고 쓸 수 있게
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
