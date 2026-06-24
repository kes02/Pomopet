import Foundation
import SwiftUI
import Combine
import Sparkle

// MARK: - UpdaterManager
// Sparkle 자동 업데이트 래퍼. SwiftUI에서 "업데이트 확인" 버튼 + 자동(스케줄) 확인을 제공.
// 피드 URL·공개키·자동확인 설정은 Info.plist(SUFeedURL / SUPublicEDKey / SUEnableAutomaticChecks).
@MainActor
final class UpdaterManager: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// "업데이트 확인" 버튼 활성화 여부 (확인 중이면 false).
    @Published var canCheckForUpdates = false

    init() {
        // startingUpdater: true → 앱 실행 시 스케줄 자동 확인 시작(SUEnableAutomaticChecks 따름).
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // canCheckForUpdates(KVO)를 발행 값에 연결 → 버튼 enable 상태 반영.
        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// 수동 "업데이트 확인" — Sparkle이 자체 창(버전·릴리스노트·설치+재시작)을 띄움.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
