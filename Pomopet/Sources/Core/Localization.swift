import Foundation
import SwiftUI
import Combine
import ObjectiveC

// MARK: - LanguageManager
// 시스템 언어와 무관하게 앱 안에서 한국어/영어를 직접 고를 수 있게 합니다.
// 선택은 UserDefaults에 저장되고, 다음 실행에도 유지됩니다.
@MainActor
final class LanguageManager: ObservableObject {
    static let supported = ["ko", "en"]
    private static let key = "appLanguage"

    /// 현재 앱 언어 코드 ("ko" / "en").
    @Published var code: String {
        didSet {
            guard code != oldValue else { return }
            UserDefaults.standard.set(code, forKey: Self.key)
            Bundle.setAppLanguage(code)   // 즉시 문자열 테이블 전환
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        let initial = saved ?? (Self.systemPrefersKorean ? "ko" : "en")
        self.code = initial
        Bundle.setAppLanguage(initial)    // 실행 시 저장된 언어로 시작
    }

    /// 날짜·숫자 포맷용 로케일 (뷰의 \.locale 환경값으로 주입).
    var locale: Locale { Locale(identifier: code) }

    func select(_ newCode: String) { code = newCode }

    private static var systemPrefersKorean: Bool {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("ko")
    }
}

// MARK: - Bundle 언어 교체 (런타임 전환)
// Bundle.main의 문자열 조회를 선택 언어의 .lproj 번들로 리다이렉트합니다.
// 시스템 언어를 바꾸지 않고도 Text("…") 자동 번역이 선택 언어를 따르게 됩니다.
nonisolated(unsafe) private var appLanguageBundleKey: UInt8 = 0

private final class AppLanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let b = objc_getAssociatedObject(self, &appLanguageBundleKey) as? Bundle {
            return b.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// Bundle.main을 선택 언어의 .lproj로 연결합니다(최초 1회 클래스 교체 + 이후 연결만 갱신).
    static func setAppLanguage(_ code: String) {
        if !(Bundle.main is AppLanguageBundle) {
            object_setClass(Bundle.main, AppLanguageBundle.self)
        }
        let lprojBundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap { Bundle(path: $0) }
        objc_setAssociatedObject(Bundle.main, &appLanguageBundleKey, lprojBundle, .OBJC_ASSOCIATION_RETAIN)
    }
}
