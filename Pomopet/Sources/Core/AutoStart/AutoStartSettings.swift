import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - 작업 시작 감지 설정
//
// 정해둔 앱(Xcode, VS Code 등)이 화면 앞으로 나오면 카운트다운 카드를 띄우고,
// 그 사이 "나중에" 를 누르지 않으면 그대로 집중을 시작합니다.
// 매번 시작 버튼을 누르는 게 번거로워서 기본값을 "시작" 쪽으로 뒀습니다.

struct TriggerApp: Codable, Identifiable, Equatable {
    let bundleID: String
    let name: String

    var id: String { bundleID }

    var icon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

struct AutoStartSettings: Codable, Equatable {
    /// 기능 자체를 쓸지
    var enabled: Bool
    /// 이 앱들이 앞으로 나오면 물어봅니다
    var apps: [TriggerApp]
    /// 앱을 잠깐 스쳐 지나간 것과 진짜 작업을 시작한 것을 구분하기 위한 대기 시간(초)
    var dwellSeconds: Int
    /// 카드가 뜬 뒤 이 초 안에 "나중에" 를 누르지 않으면 그대로 시작합니다.
    var countdownSeconds: Int
    /// 오늘 이미 집중했으면 그만 물어보기
    var skipWhenGoalMet: Bool

    static let `default` = AutoStartSettings(
        enabled: false,
        apps: [],
        dwellSeconds: 10,
        countdownSeconds: 3,
        skipWhenGoalMet: true
    )

    // 나중에 항목이 늘어도 예전 저장본을 계속 읽을 수 있게, 없는 값은 기본값으로 채웁니다.
    // (필수 항목으로 두면 항목을 하나 추가할 때마다 사용자의 앱 목록이 통째로 초기화됩니다)
    enum CodingKeys: String, CodingKey {
        case enabled, apps, dwellSeconds, countdownSeconds, skipWhenGoalMet
    }

    init(enabled: Bool, apps: [TriggerApp], dwellSeconds: Int, countdownSeconds: Int, skipWhenGoalMet: Bool) {
        self.enabled = enabled
        self.apps = apps
        self.dwellSeconds = dwellSeconds
        self.countdownSeconds = countdownSeconds
        self.skipWhenGoalMet = skipWhenGoalMet
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.default
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? fallback.enabled
        apps = try c.decodeIfPresent([TriggerApp].self, forKey: .apps) ?? fallback.apps
        dwellSeconds = try c.decodeIfPresent(Int.self, forKey: .dwellSeconds) ?? fallback.dwellSeconds
        countdownSeconds = try c.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? fallback.countdownSeconds
        skipWhenGoalMet = try c.decodeIfPresent(Bool.self, forKey: .skipWhenGoalMet) ?? fallback.skipWhenGoalMet
    }

    static let storageKey = "pomopet.autoStart"

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func load() -> AutoStartSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return .default }
        do {
            return try JSONDecoder().decode(AutoStartSettings.self, from: data)
        } catch {
            // 여기까지 오면 저장본이 정말 깨진 경우. 기본값으로 시작하되 원본은 덮어쓰지 않습니다.
            return .default
        }
    }
}

// MARK: - 앱 고르기
/// `/Applications` 에서 앱을 골라 bundle id 를 읽어옵니다.
func pickApplication() -> TriggerApp? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.prompt = String(localized: "선택")

    guard panel.runModal() == .OK,
          let url = panel.url,
          let bundle = Bundle(url: url),
          let bundleID = bundle.bundleIdentifier
    else { return nil }

    let name = (bundle.infoDictionary?["CFBundleName"] as? String)
        ?? url.deletingPathExtension().lastPathComponent
    return TriggerApp(bundleID: bundleID, name: name)
}
