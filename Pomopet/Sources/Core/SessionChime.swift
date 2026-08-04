import AppKit

// MARK: - 세션 알림음
//
// 집중이 끝나는 순간 사용자는 대개 다른 앱을 보고 있습니다. 화면 구석에 카드가 떠도
// 눈이 그쪽에 없으면 못 봅니다. 소리는 화면을 보고 있지 않아도 닿습니다.
//
// 번들에 음원을 넣지 않고 시스템 소리를 씁니다 — 시스템 소리는 사용자가 이미 볼륨을
// 맞춰둔 것이고, 직접 넣은 음원은 다른 앱 알림과 톤이 어긋납니다.
enum SessionChime {

    /// 집중 세션이 끝났을 때.
    static func playCompletion() {
        play(named: "Glass")
    }

    private static func play(named name: String) {
        guard let sound = NSSound(named: name) else {
            NSSound.beep()   // 시스템 소리를 못 찾는 환경이면 기본 알림음이라도
            return
        }
        sound.play()
    }
}
