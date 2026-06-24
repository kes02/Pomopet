import SwiftUI

// MARK: - CharacterView
// 업로드한 캐릭터를 도트로 그립니다.
// 활성(오늘 목표 달성) = 풀컬러로 통통 튀고 빛남 / 잠듦 = 흑백으로 정지.
struct CharacterView: View {
    let grid: [[Color?]]
    var tint: Color = .accentColor
    var active: Bool = false
    var size: CGFloat = 96

    var body: some View {
        if active {
            // 활성: 풀컬러 + 통통 튀기.
            // phaseAnimator는 애니메이션을 스스로(내부 상태로) 구동하므로, 집중/휴식
            // 카운트다운으로 팝오버가 매초 다시 그려져도 끊기거나 깜빡이지 않는다.
            // (기존 .repeatForever 방식은 리렌더마다 애니메이션이 리셋돼 깜빡였음)
            sprite.phaseAnimator([CGFloat(2), -2]) { view, y in
                view.offset(y: y)
            } animation: { _ in
                .easeInOut(duration: 1.0)
            }
        } else {
            // 잠듦: 흑백으로 정지
            sprite.offset(y: 2)
        }
    }

    // 스프라이트 본체. 밝기·그림자는 active에만 의존하므로 통통 튀는 동안 밝기는 일정하다.
    private var sprite: some View {
        ColorGridView(grid: grid, size: size)
            .saturation(active ? 1.0 : 0.12)
            .opacity(active ? 1.0 : 0.5)
            .shadow(color: active ? tint.opacity(0.55) : .clear, radius: active ? 8 : 0, y: 2)
    }
}
