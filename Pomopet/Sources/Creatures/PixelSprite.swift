import SwiftUI

// MARK: - Color(hex:)
// 팔레트를 16진수로 간결하게 정의하기 위한 헬퍼.
extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

// MARK: - PixelSprite
// 도트 그래픽 한 장. 외부 이미지 없이 "문자 격자 + 팔레트"로 표현합니다.
// rows의 각 문자가 palette의 키이고, '.'(또는 매핑 없는 문자)는 투명입니다.
struct PixelSprite: Hashable {
    let rows: [String]
    let palette: [Character: Color]

    /// 가장 긴 행 기준 가로 픽셀 수 (행 길이가 달라도 안전하게 처리)
    var width: Int { rows.map(\.count).max() ?? 0 }
    var height: Int { rows.count }
}

// MARK: - PixelSpriteView
// PixelSprite를 화면에 또렷한 픽셀로 그립니다. Canvas로 셀마다 사각형을 채웁니다.
struct PixelSpriteView: View {
    let sprite: PixelSprite
    var size: CGFloat = 80

    var body: some View {
        Canvas { context, canvasSize in
            let cols = sprite.width
            let rows = sprite.height
            guard cols > 0, rows > 0 else { return }

            // 정사각 픽셀 크기 (격자가 캔버스에 꽉 차도록)
            let cell = min(canvasSize.width / CGFloat(cols),
                           canvasSize.height / CGFloat(rows))
            // 가운데 정렬 오프셋
            let originX = (canvasSize.width - cell * CGFloat(cols)) / 2
            let originY = (canvasSize.height - cell * CGFloat(rows)) / 2

            for (r, line) in sprite.rows.enumerated() {
                for (c, ch) in line.enumerated() {
                    guard let color = sprite.palette[ch] else { continue }
                    // +0.6: 셀 사이 hairline 틈을 메워 빈틈 없이 보이게 함
                    let rect = CGRect(
                        x: originX + CGFloat(c) * cell,
                        y: originY + CGFloat(r) * cell,
                        width: cell + 0.6,
                        height: cell + 0.6
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - SpriteBook
// 진화 단계별 "실루엣(모양)"을 정의합니다. 색은 종(Species)의 palette에서 입혀집니다.
// 문자 의미: 1=외곽선, 2=몸체, 3=배(그림자), 4=장식, 5=장식 하이라이트, e=눈, w=흰자.
enum SpriteBook {
    static func rows(for stage: EvolutionStage) -> [String] {
        switch stage {
        case .egg:   return egg
        case .baby:  return baby
        case .teen:  return teen
        case .adult: return adult
        }
    }

    // 알: 종 색으로 물든 알 + 무늬 점(5)
    static let egg = [
        "................",
        "......1111......",
        ".....133331.....",
        "....13333331....",
        "...1335333531...",
        "...1333333331...",
        "..133333333331..",
        "..135333335331..",
        "..133333333331..",
        "..133333333331..",
        "...1333533331...",
        "...1333333331...",
        "....13333331....",
        ".....133331.....",
        "......1111......",
        "................",
    ]

    // 아기: 작고 동그란 몸 + 머리 장식
    static let baby = [
        "................",
        ".......44.......",
        "......4554......",
        "......1111......",
        ".....122221.....",
        "....12222221....",
        "...12e2222e21...",
        "...1222222221...",
        "...1233333321...",
        "...1222222221...",
        "....12222221....",
        ".....122221.....",
        "......1111......",
        ".....11..11.....",
        "................",
        "................",
    ]

    // 성장기: 더 커지고 다리가 생김
    static let teen = [
        "................",
        ".......44.......",
        "......4554......",
        "......4554......",
        "......1111......",
        ".....122221.....",
        "....12e22e21....",
        "....12222221....",
        "...1222222221...",
        "..122222222221..",
        "..123333333321..",
        "..122222222221..",
        "...1222222221...",
        "....11111111....",
        "....1.1..1.1....",
        "................",
    ]

    // 완전체: 격자를 꽉 채우는 큰 몸 + 머리 장식 크라운 + 입
    static let adult = [
        "................",
        ".......44.......",
        "......4554......",
        ".....455554.....",
        "......1111......",
        ".....122221.....",
        "....12222221....",
        "...12e2222e21...",
        "...1222222221...",
        "...1222112221...",
        "..122222222221..",
        ".12233333333221.",
        ".12233333333221.",
        ".12222222222221.",
        "..122222222221..",
        "...11.....11....",
    ]
}
