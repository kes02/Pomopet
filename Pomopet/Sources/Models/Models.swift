import Foundation
import SwiftData

// MARK: - 현재 키우고 있는 생물
// SwiftData 모델. 앱을 꺼도 디스크에 저장됩니다.
@Model
final class Creature {
    var id: UUID
    var speciesId: String        // 어떤 종인지 (SpeciesCatalog 참고)
    var sessionsCompleted: Int   // 이 생물에 누적된 집중 세션 수
    var isCompleted: Bool        // 완전체에 도달했는지
    var createdAt: Date
    var completedAt: Date?

    init(speciesId: String) {
        self.id = UUID()
        self.speciesId = speciesId
        self.sessionsCompleted = 0
        self.isCompleted = false
        self.createdAt = Date()
        self.completedAt = nil
    }

    /// 현재 진화 단계 (누적 세션에서 계산)
    var stage: EvolutionStage {
        EvolutionStage.stage(for: sessionsCompleted)
    }

    /// 레벨. 집중 세션을 완료할 때마다 1씩 오릅니다 (Lv.1 알 → Lv.10 완전체).
    var level: Int { sessionsCompleted + 1 }

    /// 이 종의 정의
    var species: Species {
        SpeciesCatalog.species(for: speciesId)
    }

    /// 다음 단계까지 남은 세션 수. 완전체면 nil.
    var sessionsToNextStage: Int? {
        let current = stage
        guard let nextStage = EvolutionStage(rawValue: current.rawValue + 1) else {
            return nil // 이미 완전체
        }
        return max(0, nextStage.sessionsRequired - sessionsCompleted)
    }

    /// 현재 단계 안에서의 진행률 (0.0 ~ 1.0). 진행바 표시에 사용.
    var progressWithinStage: Double {
        let current = stage
        guard let nextStage = EvolutionStage(rawValue: current.rawValue + 1) else {
            return 1.0 // 완전체는 꽉 찬 상태
        }
        let base = current.sessionsRequired
        let target = nextStage.sessionsRequired
        let span = target - base
        guard span > 0 else { return 1.0 }
        let done = sessionsCompleted - base
        return min(1.0, max(0.0, Double(done) / Double(span)))
    }
}

// MARK: - 도감 기록
// 완성한 생물을 영구 기록합니다.
@Model
final class CollectionEntry {
    var speciesId: String
    var completedAt: Date

    init(speciesId: String, completedAt: Date) {
        self.speciesId = speciesId
        self.completedAt = completedAt
    }
}

// MARK: - 전체 통계
// 앱 전역의 누적 통계. 보통 한 개의 인스턴스만 존재합니다.
@Model
final class AppStats {
    var totalFocusSessions: Int
    var totalFocusMinutes: Int
    var creaturesCompleted: Int

    init() {
        self.totalFocusSessions = 0
        self.totalFocusMinutes = 0
        self.creaturesCompleted = 0
    }
}
