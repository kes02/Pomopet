import SwiftUI

// MARK: - StatsView
// 누적 통계 + 연속 기록 + 최근 활동 히트맵(잔디).
struct StatsView: View {
    @ObservedObject var controller: PomopetController

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                statRow(label: "현재 연속", value: "🔥 \(controller.currentStreak)일")
                statRow(label: "최고 연속", value: "\(controller.bestStreak)일")
                statRow(label: "총 집중 세션", value: "\(controller.totalFocusSessions)회")
                statRow(label: "총 집중 시간", value: formatMinutes(controller.totalFocusMinutes))
            }

            Divider()

            Text("최근 활동")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HeatmapView(days: controller.recentDays, tint: PetVisual.tint())
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

// MARK: - HeatmapView
// 최근 35일(7열×5행) 활동 격자. 세션 수가 많을수록 진해집니다.
struct HeatmapView: View {
    let days: [DayCell]
    let tint: Color

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days) { day in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color(for: day.sessions))
                    .frame(height: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(.white.opacity(day.isToday ? 0.8 : 0), lineWidth: 1)
                    )
            }
        }
    }

    private func color(for sessions: Int) -> Color {
        switch sessions {
        case 0:      return .gray.opacity(0.15)
        case 1:      return tint.opacity(0.4)
        case 2:      return tint.opacity(0.6)
        case 3:      return tint.opacity(0.8)
        default:     return tint
        }
    }
}

// MARK: - SettingsView
// 타이머 길이 + 일일 목표 + 캐릭터 변경.
struct SettingsView: View {
    @ObservedObject var controller: PomopetController
    @State private var focus: Double
    @State private var breakV: Double
    @State private var dailyGoal: Double
    @State private var didSave = false

    init(controller: PomopetController) {
        self.controller = controller
        _focus = State(initialValue: Double(controller.settings.focusMinutes))
        _breakV = State(initialValue: Double(controller.settings.breakMinutes))
        _dailyGoal = State(initialValue: Double(controller.settings.dailyGoalSessions))
    }

    var body: some View {
        VStack(spacing: 14) {
            sliderRow(title: "집중", value: $focus, range: 5...60, unit: "분")
            sliderRow(title: "휴식", value: $breakV, range: 1...30, unit: "분")
            sliderRow(title: "하루 목표", value: $dailyGoal, range: 1...20, unit: "세션")

            VStack(spacing: 4) {
                Button("저장") {
                    var s = controller.settings
                    s.focusMinutes = Int(focus)
                    s.breakMinutes = Int(breakV)
                    s.dailyGoalSessions = Int(dailyGoal)
                    controller.updateSettings(s)
                    showSavedMessage()
                }
                .buttonStyle(.borderedProminent)

                Label("저장되었습니다", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .opacity(didSave ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: didSave)
            }
            // 값을 수정하면 저장 메시지를 숨겨 현재 상태를 반영
            .onChange(of: focus) { didSave = false }
            .onChange(of: breakV) { didSave = false }
            .onChange(of: dailyGoal) { didSave = false }

            Divider()

            Button("캐릭터 바꾸기") {
                if let image = pickImageFile() {
                    controller.changeCharacter(image)
                }
            }
            .buttonStyle(.bordered)
            .help("연속 기록은 그대로 유지돼요")

            Button("Pomopet 종료") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }

    private func showSavedMessage() {
        didSave = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            didSave = false
        }
    }

    private func sliderRow(title: String, value: Binding<Double>,
                           range: ClosedRange<Double>, unit: String) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text("\(Int(value.wrappedValue))\(unit)").font(.callout).fontWeight(.semibold)
            }
            Slider(value: value, in: range, step: 1)
        }
    }
}
