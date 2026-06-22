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
    let id: String                    // 고유 식별자 (예: "sprout")
    let name: String                  // 표시 이름 (예: "새싹이")
    let color: Color                  // 대표 색 (진행바·메뉴바 등 UI 강조용)
    let symbols: [String]             // 단계별 SF Symbol 이름 (메뉴바 라벨용)
    let palette: [Character: Color]   // 픽셀 스프라이트 색 팔레트

    /// 특정 단계의 SF Symbol 이름을 반환합니다 (메뉴바 라벨에 사용).
    func symbol(for stage: EvolutionStage) -> String {
        let index = stage.rawValue
        guard index < symbols.count else { return symbols.last ?? "questionmark" }
        return symbols[index]
    }

    /// 특정 단계의 픽셀 스프라이트(공유 실루엣 + 이 종의 팔레트).
    func sprite(for stage: EvolutionStage) -> PixelSprite {
        PixelSprite(rows: SpriteBook.rows(for: stage), palette: palette)
    }
}

// MARK: - 팔레트 헬퍼
// 종마다 외곽선/몸체/그림자/장식 색을 지정하면 스프라이트 전체에 입혀집니다.
private func makePalette(outline: UInt, body: UInt, belly: UInt,
                         accent: UInt, accentLight: UInt) -> [Character: Color] {
    [
        "1": Color(hex: outline),
        "2": Color(hex: body),
        "3": Color(hex: belly),
        "4": Color(hex: accent),
        "5": Color(hex: accentLight),
        "e": Color(hex: 0x20242e),  // 눈동자
        "w": .white,                // 흰자/하이라이트
    ]
}

// MARK: - 모든 종 목록
// 새 생물을 추가하려면 이 배열에 항목만 추가하면 됩니다.
enum SpeciesCatalog {
    static let all: [Species] = [
        Species(
            id: "sprout",
            name: "새싹이",
            color: .green,
            symbols: ["oval.fill", "leaf", "leaf.fill", "tree.fill"],
            palette: makePalette(
                outline: 0x1b3a1b, body: 0x3fae54, belly: 0x2e7d3f,
                accent: 0x7ed957, accentLight: 0xb6f09c
            )
        ),
        Species(
            id: "flame",
            name: "불씨",
            color: .orange,
            symbols: ["oval.fill", "flame", "flame.fill", "flame.circle.fill"],
            palette: makePalette(
                outline: 0x5c1a00, body: 0xff7a33, belly: 0xd24a17,
                accent: 0xffd23f, accentLight: 0xffe98a
            )
        ),
        Species(
            id: "droplet",
            name: "물방울",
            color: .blue,
            symbols: ["oval.fill", "drop", "drop.fill", "drop.circle.fill"],
            palette: makePalette(
                outline: 0x0a2a52, body: 0x3aa0ff, belly: 0x1e6fcc,
                accent: 0x5fe0ff, accentLight: 0xbff2ff
            )
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
