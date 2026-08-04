import Foundation

// MARK: - UserDefaults 에 Codable 저장
//
// 설정과 진행 상태를 JSON 으로 바꿔 UserDefaults 에 넣는 코드가 여러 곳에 같은 모양으로 있었습니다.
// 옮겨 적으면서 조금씩 어긋나는 게 문제라 한 곳으로 모읍니다.
//
// 실패했을 때의 규칙도 함께 정합니다.
//  * 저장 실패 — 그냥 넘어갑니다. 설정 하나 때문에 앱이 멈출 이유가 없고, 다음 저장 때 다시 씁니다.
//  * 읽기 실패 — nil 을 돌려주고, 무엇을 대신 쓸지는 부르는 쪽이 정합니다.
//    저장본은 그대로 둡니다. 덮어써 버리면 손댈 수 있었던 기록까지 사라집니다.
enum DefaultsStore {

    static func save<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func remove(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
