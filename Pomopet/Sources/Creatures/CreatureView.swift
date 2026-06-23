import SwiftUI

// MARK: - CharacterView
// 업로드한 캐릭터를 도트로 그립니다.
// 활성(오늘 목표 달성) = 풀컬러로 통통 튀고 빛남 / 잠듦 = 흑백으로 정지.
struct CharacterView: View {
    let grid: [[Color?]]
    var tint: Color = .accentColor
    var active: Bool = false
    var size: CGFloat = 96

    @State private var bob = false

    var body: some View {
        ColorGridView(grid: grid, size: size)
            .saturation(active ? 1.0 : 0.12)
            .opacity(active ? 1.0 : 0.5)
            .shadow(color: active ? tint.opacity(0.55) : .clear, radius: active ? 8 : 0, y: 2)
            .offset(y: (active && bob) ? -2 : 2)
            .animation(
                active
                    ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                    : .default,
                value: bob
            )
            .onAppear { bob = true }
    }
}
