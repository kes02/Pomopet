import SwiftUI

// MARK: - 시간 표기
// 팝오버·통계·친구 목록이 같은 규칙으로 시간을 적도록 한 곳에 둡니다.

/// 오늘 집중한 시간을 사람이 읽는 형태로.
/// 문자열 카탈로그를 타도록 LocalizedStringKey 로 돌려줍니다(영문 전환 시 번역됨).
func focusMinutesLabel(_ minutes: Int) -> LocalizedStringKey {
    let h = minutes / 60
    let m = minutes % 60
    return h > 0 ? "\(h)시간 \(m)분" : "\(m)분"
}
