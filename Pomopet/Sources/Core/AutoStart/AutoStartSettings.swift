import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - 작업 시작 감지 설정
//
// 정해둔 앱(Xcode, VS Code 등)이 화면 앞으로 나오면 "집중 시작할까요?" 하고 물어봅니다.
// 마음대로 타이머를 켜지는 않습니다 — 물어보기만 하고, 시작할지는 사용자가 정합니다.

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
    /// 오늘 목표를 이미 채웠으면 그만 물어보기
    var skipWhenGoalMet: Bool

    static let `default` = AutoStartSettings(
        enabled: false,
        apps: [],
        dwellSeconds: 10,
        skipWhenGoalMet: true
    )

    static let storageKey = "pomopet.autoStart"

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func load() -> AutoStartSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(AutoStartSettings.self, from: data)
        else { return .default }
        return decoded
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
