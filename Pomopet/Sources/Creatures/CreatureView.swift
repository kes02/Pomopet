import SwiftUI

// MARK: - CreatureView
// 생물 한 마리를 화면에 그립니다. 외부 이미지 없이 SF Symbol + 도형으로 표현.
struct CreatureView: View {
    let species: Species
    let stage: EvolutionStage
    var size: CGFloat = 80

    @State private var bounce = false

    var body: some View {
        ZStack {
            // 부드러운 배경 원 (단계가 올라갈수록 진해짐)
            Circle()
                .fill(species.color.opacity(0.12 + Double(stage.rawValue) * 0.06))
                .frame(width: size, height: size)

            // 알 단계는 알 모양 + 무늬, 그 외에는 종 심볼
            if stage == .egg {
                eggView
            } else {
                Image(systemName: species.symbol(for: stage))
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(species.color)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .scaleEffect(bounce ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: bounce)
        .onAppear { bounce = true }
    }

    // 알 단계 전용 그림
    private var eggView: some View {
        ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [species.color.opacity(0.5), species.color.opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.42, height: size * 0.55)
            // 알 무늬 점 두 개
            VStack(spacing: size * 0.06) {
                Circle().fill(.white.opacity(0.5)).frame(width: size * 0.07, height: size * 0.07)
                Circle().fill(.white.opacity(0.5)).frame(width: size * 0.05, height: size * 0.05)
            }
        }
    }
}
