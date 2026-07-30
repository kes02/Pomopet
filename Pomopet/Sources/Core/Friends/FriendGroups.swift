import Foundation

// MARK: - 친구 그룹
//
// 그룹은 **이 맥에만** 저장됩니다. 서버로 보내지 않아요.
//
// 그룹은 "내가 보기 편하려고 나누는 것"이지 친구와 공유하는 정보가 아닙니다.
// 친구 입장에서 자기가 어느 그룹에 들어 있는지 알 이유도 없고, 알면 오히려 불편합니다.
// 그래서 서버에 올리지 않고 UserDefaults 에만 둡니다 — 서버 코드도, 개인정보도 늘어나지 않습니다.

struct FriendGroup: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// 이 그룹에 속한 친구들의 코드
    var codes: [String]

    init(name: String, codes: [String] = []) {
        self.id = UUID().uuidString
        self.name = name
        self.codes = codes
    }
}

enum FriendGroupStore {
    private static let key = "pomopet.friendGroups"

    static func load() -> [FriendGroup] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let groups = try? JSONDecoder().decode([FriendGroup].self, from: data)
        else { return [] }
        return groups
    }

    static func save(_ groups: [FriendGroup]) {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
