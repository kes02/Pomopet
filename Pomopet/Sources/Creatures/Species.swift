import SwiftUI

// MARK: - 진화 단계
// 생물이 거치는 4개의 단계를 표현합니다.
enum EvolutionStage: Int, CaseIterable {
    case egg = 0      // 알
    case baby = 1     // 아기
    case teen = 2     // 성장기
    case adult = 3    // 완전체

    /// 각 단계에 도달하기 위해 필요한 누적 집중 세션 수
    var sessionsRequired: Int {
        switch self {
        case .egg:   return 0
        case .baby:  return 2
        case .teen:  return 5
        case .adult: return 9
        }
    }

    var displayName: String {
        switch self {
        case .egg:   return "알"
        case .baby:  return "아기"
        case .teen:  return "성장기"
        case .adult: return "완전체"
        }
    }

    /// 누적 세션 수로부터 현재 단계를 계산합니다.
    static func stage(for sessions: Int) -> EvolutionStage {
        // 높은 단계부터 검사하여 조건을 만족하는 가장 높은 단계를 반환
        for stage in EvolutionStage.allCases.reversed() {
            if sessions >= stage.sessionsRequired {
                return stage
            }
        }
        return .egg
    }
}

// MARK: - 종(Species) 정의
// 하나의 생물 종이 4개 단계에서 어떻게 보이는지를 정의합니다.
// 그래픽은 외부 이미지 없이 SF Symbol 이름 + 색으로 표현합니다.
struct Species: Identifiable, Hashable {
    let id: String          // 고유 식별자 (예: "sprout")
    let name: String        // 표시 이름 (예: "새싹이")
    let color: Color        // 대표 색
    let symbols: [String]   // 단계별 SF Symbol 이름 [알, 아기, 성장기, 완전체]

    /// 특정 단계의 SF Symbol 이름을 반환합니다.
    func symbol(for stage: EvolutionStage) -> String {
        let index = stage.rawValue
        guard index < symbols.count else { return symbols.last ?? "questionmark" }
        return symbols[index]
    }
}

// MARK: - 모든 종 목록
// 새 생물을 추가하려면 이 배열에 항목만 추가하면 됩니다.
enum SpeciesCatalog {
    static let all: [Species] = [
        Species(
            id: "sprout",
            name: "새싹이",
            color: .green,
            symbols: ["oval.fill", "leaf", "leaf.fill", "tree.fill"]
        ),
        Species(
            id: "flame",
            name: "불씨",
            color: .orange,
            symbols: ["oval.fill", "flame", "flame.fill", "flame.circle.fill"]
        ),
        Species(
            id: "droplet",
            name: "물방울",
            color: .blue,
            symbols: ["oval.fill", "drop", "drop.fill", "drop.circle.fill"]
        )
    ]

    static func species(for id: String) -> Species {
        all.first(where: { $0.id == id }) ?? all[0]
    }

    /// 다음에 부화할 종을 무작위로 고릅니다.
    static func randomSpeciesId() -> String {
        all.randomElement()?.id ?? all[0].id
    }
}
