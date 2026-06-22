import SwiftUI

// MARK: - CreatureView
// 생물 한 마리를 픽셀 도트로 그립니다. 가만히 있을 때 살짝 위아래로 통통 튑니다.
struct CreatureView: View {
    let species: Species
    let stage: EvolutionStage
    var size: CGFloat = 80

    @State private var bob = false

    var body: some View {
        PixelSpriteView(sprite: species.sprite(for: stage), size: size)
            // 도트가 흐려지지 않도록 그림자는 은은하게만
            .shadow(color: species.color.opacity(0.35), radius: 6, y: 2)
            .offset(y: bob ? -2 : 2)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: bob)
            .onAppear { bob = true }
    }
}
