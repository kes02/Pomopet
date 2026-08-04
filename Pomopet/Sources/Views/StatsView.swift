import SwiftUI
import AppKit

// MARK: - StatsView
// 누적 통계 + 연속 기록 + 최근 활동 히트맵(잔디).
struct StatsView: View {
    @ObservedObject var controller: PomopetController

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                statRow(label: "현재 연속", value: "🔥 \(controller.currentStreak)일")
                statRow(label: "최고 연속", value: "\(controller.bestStreak)일")
                statRow(label: "총 집중 시간", value: formatMinutes(controller.totalFocusMinutes))
            }

            Divider()

            HStack {
                Text("활동")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                HeatmapLegend(tint: PetVisual.tint())
            }

            HeatmapView(dayStats: controller.dayStats, tint: PetVisual.tint())
        }
    }

    private func statRow(label: LocalizedStringKey, value: LocalizedStringKey) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            Text(value).font(.callout).fontWeight(.semibold)
        }
    }

    private func formatMinutes(_ minutes: Int) -> LocalizedStringKey {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return "\(h)시간 \(m)분" }
        return "\(m)분"
    }
}
