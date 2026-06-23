import Foundation
import SwiftData

// MARK: - 하루 활동 기록
// 공부한 날짜별 집중 세션/시간을 기록합니다. 스트릭·히트맵의 원천 데이터.
@Model
final class DailyRecord {
    var dayKey: Int       // yyyyMMdd (날짜 비교/정렬용 정수 키)
    var date: Date        // 그 날의 자정 (표시용)
    var sessions: Int     // 그 날 완료한 집중 세션 수
    var minutes: Int      // 그 날 누적 집중 시간(분)
    var activated: Bool   // 그 날 목표를 달성했는지. 한번 true면 목표가 바뀌어도 유지(sticky)

    init(dayKey: Int, date: Date) {
        self.dayKey = dayKey
        self.date = date
        self.sessions = 0
        self.minutes = 0
        self.activated = false
    }
}

// MARK: - 전체 통계
// 앱 전역의 누적 통계. 보통 한 개의 인스턴스만 존재합니다.
@Model
final class AppStats {
    var totalFocusSessions: Int
    var totalFocusMinutes: Int
    var bestStreak: Int        // 역대 최고 연속일

    init() {
        self.totalFocusSessions = 0
        self.totalFocusMinutes = 0
        self.bestStreak = 0
    }
}
