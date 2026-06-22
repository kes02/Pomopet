import SwiftUI

// MARK: - StatsView
// 누적 통계와 도감을 보여줍니다.
struct StatsView: View {
    @ObservedObject var controller: PomopetController

    var body: some View {
        VStack(spacing: 14) {
            if let stats = controller.stats {
                VStack(spacing: 10) {
                    statRow(label: "총 집중 세션", value: "\(stats.totalFocusSessions)회")
                    statRow(label: "총 집중 시간", value: formatMinutes(stats.totalFocusMinutes))
                    statRow(label: "완성한 생물", value: "\(stats.creaturesCompleted)마리")
                }
            }

            Divider()

            // 도감: 완성한 종류를 보여줌
            Text("도감")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                ForEach(SpeciesCatalog.all) { species in
                    VStack(spacing: 2) {
                        Image(systemName: species.symbol(for: .adult))
                            .font(.system(size: 22))
                            .foregroundStyle(species.color)
                            .symbolRenderingMode(.hierarchical)
                        Text(species.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            Text(value).font(.callout).fontWeight(.semibold)
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return "\(h)시간 \(m)분" }
        return "\(m)분"
    }
}

// MARK: - SettingsView
// 타이머 길이를 조정합니다.
struct SettingsView: View {
    @ObservedObject var controller: PomopetController
    @State private var focus: Double
    @State private var shortBreak: Double
    @State private var longBreak: Double

    init(controller: PomopetController) {
        self.controller = controller
        _focus = State(initialValue: Double(controller.settings.focusMinutes))
        _shortBreak = State(initialValue: Double(controller.settings.shortBreakMinutes))
        _longBreak = State(initialValue: Double(controller.settings.longBreakMinutes))
    }

    var body: some View {
        VStack(spacing: 14) {
            sliderRow(title: "집중", value: $focus, range: 5...60)
            sliderRow(title: "짧은 휴식", value: $shortBreak, range: 1...30)
            sliderRow(title: "긴 휴식", value: $longBreak, range: 5...45)

            Button("저장") {
                var s = controller.settings
                s.focusMinutes = Int(focus)
                s.shortBreakMinutes = Int(shortBreak)
                s.longBreakMinutes = Int(longBreak)
                controller.updateSettings(s)
            }
            .buttonStyle(.borderedProminent)

            Divider()

            Button("Pomopet 종료") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text("\(Int(value.wrappedValue))분").font(.callout).fontWeight(.semibold)
            }
            Slider(value: value, in: range, step: 1)
        }
    }
}
