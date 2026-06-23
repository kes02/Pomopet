import Foundation
import SwiftUI
import Combine
import AppKit

// MARK: - UpdateChecker
// GitHub Releases를 조회해 새 버전이 있으면 알려주는 가벼운 인앱 업데이트 체크.
// 미서명 빌드라 "자동 설치"는 하지 않습니다 — "새 버전 있어요 → 다운로드 페이지 열기"만 안내.
// 자동 확인은 하루 1회, 사용자가 닫은 버전은 다음 새 버전 전까지 다시 띄우지 않습니다.
@MainActor
final class UpdateChecker: ObservableObject {

    // MARK: 발행 상태 (뷰가 자동 반응)
    @Published private(set) var latestVersion: String?   // 최신 릴리스 버전 (예: "1.1.0")
    @Published private(set) var releaseURL: URL?         // 해당 릴리스 페이지
    /// 한 번의 확인 결과. check()가 "반환"만 하고 어디에도 저장하지 않습니다 —
    /// 그래서 "최신 버전이에요" 같은 메시지가 화면을 열 때마다 다시 뜨지 않습니다.
    /// (메시지를 잠깐 보여줄지 말지는 호출하는 뷰가 관리)
    enum CheckOutcome: Equatable {
        case upToDate     // 최신 버전
        case updateFound  // 새 버전 있음
        case rateLimited  // GitHub API 호출 한도 초과 (미인증 IP당 60회/시간)
        case failed       // 네트워크 등 기타 실패
    }

    /// 현재 앱 버전 (Info.plist CFBundleShortVersionString, 예: "1.0")
    let current: String = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"

    /// 새 버전 배너를 띄울지: 더 높은 버전이 있고 + 사용자가 그 버전을 닫지 않았을 때
    var updateAvailable: Bool {
        guard let latest = latestVersion,
              Self.compare(latest, current) == .orderedDescending else { return false }
        return dismissedVersion != latest
    }

    // GitHub Releases API (최신 정식 릴리스 1건)
    private let apiURL = URL(string: "https://api.github.com/repos/kes02/Pomopet/releases/latest")!
    private let fallbackPage = URL(string: "https://github.com/kes02/Pomopet/releases/latest")!

    // UserDefaults 키
    private let lastCheckKey = "updateChecker.lastCheck"
    private let dismissedKey = "updateChecker.dismissedVersion"

    private var dismissedVersion: String? {
        get { UserDefaults.standard.string(forKey: dismissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: dismissedKey) }
    }

    // MARK: - 확인

    /// 자동 확인: 마지막 확인으로부터 24시간이 지났을 때만 네트워크를 탑니다.
    func checkIfDue() async {
        if let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < 24 * 60 * 60 { return }
        await check()
    }

    /// 새 버전 확인. 결과를 "반환"만 하고 저장하지 않습니다 — 메시지 표시/숨김은 호출하는 뷰가 관리.
    /// (자동 확인은 결과를 버리고 배너 데이터만 갱신, 수동 확인만 잠깐 메시지를 보여줍니다.)
    @discardableResult
    func check() async -> CheckOutcome {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Pomopet-macOS-app", forHTTPHeaderField: "User-Agent") // GitHub API는 UA 헤더 필수
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            // 403/429 = 호출 한도 초과 (미인증은 IP당 60회/시간). lastCheck를 갱신하지 않아 곧 재시도됨.
            if http.statusCode == 403 || http.statusCode == 429 { return .rateLimited }
            guard http.statusCode == 200 else { return .failed }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            UserDefaults.standard.set(Date(), forKey: lastCheckKey) // 성공했을 때만 기록
            // tag_name 예: "v1.1.0" → 앞의 'v' 제거
            let tag = release.tagName
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            latestVersion = version
            releaseURL = URL(string: release.htmlURL)
            return Self.compare(version, current) == .orderedDescending ? .updateFound : .upToDate
        } catch {
            return .failed // 네트워크 실패
        }
    }

    // MARK: - 사용자 액션

    /// 다운로드(릴리스) 페이지를 브라우저로 엽니다.
    func openReleasePage() {
        NSWorkspace.shared.open(releaseURL ?? fallbackPage)
    }

    /// 이 버전 알림을 닫습니다 — 다음 새 버전이 나올 때까지 배너가 다시 뜨지 않습니다.
    func dismissCurrentNotice() {
        dismissedVersion = latestVersion
        objectWillChange.send()
    }

    // MARK: - 버전 비교
    // "1.0" vs "1.0.1" 처럼 자리수가 달라도 안전하게 비교 (모자란 자리는 0으로 간주).
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

// GitHub Releases API 응답 (필요한 필드만)
private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
