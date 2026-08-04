import SwiftUI

// MARK: - 펫 화면
//
// 펫이 서 있는 어두운 "게임 화면" 패널의 색.
//
// 팝오버·업로드 미리보기·친구 목록 썸네일이 모두 같은 화면을 흉내 냅니다.
// 색이 세 곳에 흩어져 있으면 한 곳만 고쳤을 때 미리보기와 실제 화면의 색이 달라져,
// "적용 전에 실제 모습을 보여준다" 는 미리보기의 목적이 깨집니다.
enum PetScreen {
    static let top = Color(hex: 0x121726)
    static let bottom = Color(hex: 0x1c2438)

    /// 큰 패널용 — 위에서 아래로 옅어집니다.
    static var background: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }
}
