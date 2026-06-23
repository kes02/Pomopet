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
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject var lang: LanguageManager
    @State private var focus: Double
    @State private var breakV: Double
    @State private var dailyGoal: Double
    @State private var didSave = false
    @State private var checking = false                        // 수동 확인 진행 중
    @State private var checkResult: UpdateChecker.CheckOutcome? // 수동 확인 직후 잠깐 보여줄 결과

    init(controller: PomopetController, updateChecker: UpdateChecker, lang: LanguageManager) {
        self.controller = controller
        self.updateChecker = updateChecker
        self.lang = lang
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
                // 캐릭터 바꾸기(좌) · 저장(우)
                HStack {
                    Button("캐릭터 바꾸기") {
                        if let image = pickImageFile() {
                            controller.changeCharacter(image)
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("연속 기록은 그대로 유지돼요")

                    Spacer()

                    Button("저장") {
                        var s = controller.settings
                        s.focusMinutes = Int(focus)
                        s.breakMinutes = Int(breakV)
                        s.dailyGoalSessions = Int(dailyGoal)
                        controller.updateSettings(s)
                        showSavedMessage()
                    }
                    .buttonStyle(.borderedProminent)
                }

                // 저장 버튼이 우측이라 확인 메시지도 우측 정렬
                Label("저장되었습니다", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .opacity(didSave ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: didSave)
            }
            // 값을 수정하면 저장 메시지를 숨겨 현재 상태를 반영
            .onChange(of: focus) { didSave = false }
            .onChange(of: breakV) { didSave = false }
            .onChange(of: dailyGoal) { didSave = false }

            Divider()

            languageRow

            updateRow

            Button("Pomopet 종료") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }

    // 언어 전환: 시스템 언어와 무관하게 한국어/영어를 버튼으로 직접 선택.
    private var languageRow: some View {
        HStack {
            Text("언어").font(.caption).foregroundStyle(.secondary)
            Spacer()
            langButton("한국어", "ko")
            langButton("English", "en")
        }
    }

    // 언어 버튼 — 선택된 쪽은 강조(accent), 나머지는 흐리게. 라벨은 각 언어 고유명이라 verbatim.
    private func langButton(_ title: String, _ code: String) -> some View {
        let active = lang.code == code
        return Button { lang.select(code) } label: {
            Text(verbatim: title)
                .font(.caption2)
                .frame(minWidth: 46)
        }
        .buttonStyle(.borderedProminent)
        .tint(active ? .accentColor : Color.gray.opacity(0.35))
        .controlSize(.small)
    }

    // 버전 표시 + 수동 업데이트 확인. 새 버전이 있으면 버튼이 "받기"로 바뀌어 다운로드 페이지를 엽니다.
    private var updateRow: some View {
        VStack(spacing: 6) {
            HStack {
                Text("버전").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("v\(updateChecker.current)").font(.caption).foregroundStyle(.secondary)
            }

            Button {
                if updateChecker.updateAvailable {
                    updateChecker.openReleasePage()
                } else {
                    runManualCheck()
                }
            } label: {
                Group {
                    if checking {
                        Label("확인 중…", systemImage: "arrow.triangle.2.circlepath")
                    } else if updateChecker.updateAvailable {
                        Label("새 버전 \(updateChecker.latestVersion ?? "") 받기", systemImage: "arrow.down.circle")
                    } else {
                        Label("업데이트 확인", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(checking)

            // 수동 확인 직후에만 잠깐 뜨는 결과 메시지 (자동 확인·화면 재방문 시엔 안 뜸)
            if let status = manualStatus {
                Text(status.text)
                    .font(.caption2)
                    .foregroundStyle(status.color)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // "업데이트 확인"을 직접 눌렀을 때만 실행. 결과를 잠깐 보여주고 스스로 사라짐.
    private func runManualCheck() {
        checkResult = nil
        checking = true
        Task {
            let result = await updateChecker.check()
            checking = false
            checkResult = result
            // 3.5초 뒤 메시지 숨김 — 그 사이 새 결과로 덮이지 않았을 때만
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if checkResult == result { checkResult = nil }
        }
    }

    // 수동 확인 결과 → 표시할 메시지/색. (새 버전 있음은 버튼이 "받기"로 안내하므로 메시지 생략)
    private var manualStatus: (text: LocalizedStringKey, color: Color)? {
        switch checkResult {
        case .upToDate:    return ("최신 버전이에요 ✓", .green)
        case .rateLimited: return ("잠시 후 다시 시도해 주세요 (GitHub 확인 한도 초과)", .orange)
        case .failed:      return ("업데이트를 확인하지 못했어요 · 인터넷 연결을 확인해 주세요", .orange)
        case .updateFound, .none: return nil
        }
    }

    private func showSavedMessage() {
        didSave = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            didSave = false
        }
    }

    private func sliderRow(title: LocalizedStringKey, value: Binding<Double>,
                           range: ClosedRange<Double>, unit: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                (Text("\(Int(value.wrappedValue))") + Text(unit))
                    .font(.callout).fontWeight(.semibold)
            }
            Slider(value: value, in: range, step: 1)
        }
    }
}
