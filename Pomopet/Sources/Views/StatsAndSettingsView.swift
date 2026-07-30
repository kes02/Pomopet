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

// MARK: - HeatmapView
// 월 달력 형태 활동 히트맵. ‹ ›로 월 이동, 칸 색 = 세션 수, 칸에 날짜 숫자,
// 오늘은 테두리로 강조, hover 시 그날 기록(세션·집중시간)을 툴팁으로 표시.
struct HeatmapView: View {
    let dayStats: [Int: DayStat]
    let tint: Color

    @Environment(\.locale) private var locale
    @State private var monthOffset = 0   // 0 = 이번 달, -1 = 지난 달 …
    @State private var hovered: Int?     // hover 중인 날짜키 (yyyyMMdd)

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let cal = calendar
        let monthStart = monthStartDate(cal)
        return VStack(spacing: 8) {
            header(cal: cal, monthStart: monthStart)
            weekdayHeader(cal: cal)
            grid(cal: cal, monthStart: monthStart)
            detailLine(cal: cal)
        }
    }

    // 요일 순서는 시스템 지역(firstWeekday), 표기·월 이름은 앱 언어(locale)를 따른다.
    private var calendar: Calendar {
        var c = Calendar.current
        c.locale = locale
        return c
    }

    // 월 이동 헤더 + 그 달에 집중한 총 시간
    private func header(cal: Calendar, monthStart: Date) -> some View {
        VStack(spacing: 2) {
            HStack {
                Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                Spacer()
                Text(monthTitle(cal: cal, monthStart: monthStart))
                    .font(.callout).fontWeight(.semibold)
                Spacer()
                Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
                    .disabled(monthOffset >= 0)              // 미래 달로는 이동 불가
                    .opacity(monthOffset >= 0 ? 0.25 : 1)
            }
            .font(.caption)

            Text(focusMinutesLabel(monthMinutes(cal: cal, monthStart: monthStart)))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    /// 화면에 보이는 달의 집중 시간 합계(분).
    /// 날짜키가 yyyyMMdd 정수라 그 달의 범위(yyyyMM00 ~ yyyyMM99)만 걸러 더하면 됩니다.
    private func monthMinutes(cal: Calendar, monthStart: Date) -> Int {
        let comps = cal.dateComponents([.year, .month], from: monthStart)
        let base = (comps.year ?? 0) * 10000 + (comps.month ?? 0) * 100
        return dayStats
            .filter { $0.key > base && $0.key <= base + 99 }
            .values
            .reduce(0) { $0 + $1.minutes }
    }

    // 요일 머리글
    private func weekdayHeader(cal: Calendar) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(orderedWeekdaySymbols(cal).enumerated()), id: \.offset) { _, sym in
                Text(sym)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // 날짜 격자 (앞 빈칸 + 1…말일)
    private func grid(cal: Calendar, monthStart: Date) -> some View {
        let todayKey = dayKey(cal.dateComponents([.year, .month, .day], from: Date()))
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(cells(cal: cal, monthStart: monthStart)) { cell in
                if let day = cell.day, let key = cell.key {
                    dayCell(day: day, key: key, isToday: key == todayKey, cal: cal)
                } else {
                    Color.clear.frame(height: 24)
                }
            }
        }
    }

    private func dayCell(day: Int, key: Int, isToday: Bool, cal: Calendar) -> some View {
        let sessions = dayStats[key]?.sessions ?? 0
        let highlighted = hovered == key || isToday
        return RoundedRectangle(cornerRadius: 4)
            .fill(color(for: sessions))
            .frame(height: 24)
            .overlay(
                Text("\(day)")
                    .font(.system(size: 10, weight: isToday ? .bold : .regular))
                    .foregroundStyle(sessions >= 3 ? Color.white : Color.primary.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(tint, lineWidth: highlighted ? 1.5 : 0)
            )
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { hovered = key }
                else if hovered == key { hovered = nil }
            }
    }

    // hover 중인 날짜의 기록을 달력 아래 한 줄로 항상 표시.
    // (메뉴바 팝오버에서는 .help 툴팁이 안 뜨는 경우가 있어 onHover로 직접 표시)
    private func detailLine(cal: Calendar) -> some View {
        Group {
            if let key = hovered {
                recordText(key: key, cal: cal).foregroundStyle(.primary)
            } else {
                Text("날짜 위에 마우스를 올리면 그날 기록이 표시돼요").foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .frame(height: 16)
    }

    // 그날 기록을 로컬라이즈된 조각으로 구성 (각 Text가 카탈로그를 통해 번역됨).
    private func recordText(key: Int, cal: Calendar) -> Text {
        let date = Text(verbatim: dateLabel(key: key, cal: cal))
        guard let stat = dayStats[key], stat.sessions > 0 else {
            return date + Text(verbatim: " · ") + Text("기록 없음")
        }
        return date + Text(verbatim: " · ")
            + Text("\(stat.sessions)세션") + Text(verbatim: " · ")
            + minutesText(stat.minutes)
    }

    private func minutesText(_ minutes: Int) -> Text {
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? Text("\(h)시간 \(m)분") : Text("\(m)분")
    }

    // MARK: 헬퍼

    private func monthStartDate(_ cal: Calendar) -> Date {
        let now = Date()
        let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        return cal.date(byAdding: .month, value: monthOffset, to: thisMonth) ?? thisMonth
    }

    private func cells(cal: Calendar, monthStart: Date) -> [GridCell] {
        let comps = cal.dateComponents([.year, .month], from: monthStart)
        let year = comps.year ?? 2000
        let month = comps.month ?? 1
        let weekdayOfFirst = cal.component(.weekday, from: monthStart)   // 1 = 일요일
        let leading = (weekdayOfFirst - cal.firstWeekday + 7) % 7
        let dayCount = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30

        var result: [GridCell] = []
        for i in 0..<leading { result.append(GridCell(id: -1 - i, day: nil, key: nil)) }
        for d in 1...dayCount {
            let key = year * 10000 + month * 100 + d
            result.append(GridCell(id: key, day: d, key: key))
        }
        return result
    }

    private func orderedWeekdaySymbols(_ cal: Calendar) -> [String] {
        let symbols = cal.veryShortWeekdaySymbols   // 0 = 일요일
        let first = cal.firstWeekday - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private func monthTitle(cal: Calendar, monthStart: Date) -> String {
        let f = DateFormatter()
        f.calendar = cal
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("yMMMM")   // "2026년 6월" / "June 2026"
        return f.string(from: monthStart)
    }

    private func dateLabel(key: Int, cal: Calendar) -> String {
        var comps = DateComponents()
        comps.year = key / 10000
        comps.month = (key / 100) % 100
        comps.day = key % 100
        guard let date = cal.date(from: comps) else { return "\(comps.month ?? 0)/\(comps.day ?? 0)" }
        let f = DateFormatter()
        f.calendar = cal
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("MMMd")    // "6월 25일" / "Jun 25"
        return f.string(from: date)
    }

    private func dayKey(_ comps: DateComponents) -> Int {
        (comps.year ?? 0) * 10000 + (comps.month ?? 0) * 100 + (comps.day ?? 0)
    }

    // 강도 단계 색 (Less → More): 0세션 … 4+세션. 범례와 칸이 같은 색을 쓰도록 공유.
    static func intensityColors(tint: Color) -> [Color] {
        [.gray.opacity(0.15), tint.opacity(0.4), tint.opacity(0.6), tint.opacity(0.8), tint]
    }

    private func color(for sessions: Int) -> Color {
        Self.intensityColors(tint: tint)[min(max(sessions, 0), 4)]
    }

    // 달력 한 칸 (앞 빈칸 포함)
    private struct GridCell: Identifiable {
        let id: Int
        let day: Int?
        let key: Int?
    }
}

// MARK: - HeatmapLegend
// 히트맵 강도 범례 (Less → More). 단어는 영어 고정(verbatim), 색은 HeatmapView와 공유.
struct HeatmapLegend: View {
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Text(verbatim: "Less").font(.system(size: 9)).foregroundStyle(.secondary)
            ForEach(Array(HeatmapView.intensityColors(tint: tint).enumerated()), id: \.offset) { _, c in
                RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 9, height: 9)
            }
            Text(verbatim: "More").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - SettingsView
// 타이머 길이 + 일일 목표 + 캐릭터 변경.
struct SettingsView: View {
    @ObservedObject var controller: PomopetController
    @ObservedObject var updater: UpdaterManager
    @ObservedObject var lang: LanguageManager
    @ObservedObject var friends: FriendStore
    @ObservedObject var workWatcher: WorkAppWatcher
    @State private var focus: Double
    @State private var breakV: Double
    @State private var dailyGoal: Double
    @State private var didSave = false
    @State private var confirmDisconnect = false
    @State private var confirmingAppRemoval: String?   // 지울지 물어보는 중인 앱의 bundleID
    @State private var confirmingRotate = false

    init(controller: PomopetController, updater: UpdaterManager, lang: LanguageManager,
         friends: FriendStore, workWatcher: WorkAppWatcher) {
        self.controller = controller
        self.updater = updater
        self.lang = lang
        self.friends = friends
        self.workWatcher = workWatcher
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

            autoStartRow

            if friends.isConnected { friendRow }

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

    // 작업 앱을 켜면 집중 시작을 권하는 기능. 마음대로 시작하지 않고 물어보기만 합니다.
    private var autoStartRow: some View {
        VStack(spacing: 6) {
            Toggle(isOn: Binding(
                get: { workWatcher.settings.enabled },
                set: { workWatcher.settings.enabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("작업 시작하면 물어보기").font(.callout)
                    Text("정해둔 앱을 켜면 집중 시작을 권해요")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            if workWatcher.settings.enabled {
                VStack(spacing: 4) {
                    ForEach(workWatcher.settings.apps) { app in
                        HStack(spacing: 6) {
                            if let icon = app.icon {
                                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                            }
                            Text(verbatim: app.name).font(.caption)
                            Spacer()
                            if confirmingAppRemoval == app.bundleID {
                                Text("뺄까요?")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Button("빼기") {
                                    workWatcher.settings.apps.removeAll { $0.bundleID == app.bundleID }
                                    confirmingAppRemoval = nil
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.mini)
                                .tint(.red)
                                Button {
                                    confirmingAppRemoval = nil
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 8))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            } else {
                                Button {
                                    confirmingAppRemoval = app.bundleID
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 8))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button {
                        if let picked = pickApplication(),
                           !workWatcher.settings.apps.contains(where: { $0.bundleID == picked.bundleID }) {
                            workWatcher.settings.apps.append(picked)
                        }
                    } label: {
                        Label("작업 앱 추가", systemImage: "plus")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if workWatcher.settings.apps.isEmpty {
                        Text("Xcode, VS Code처럼 작업할 때 켜는 앱을 골라주세요")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // 친구 연동을 켠 뒤의 관리 항목 — 코드 재발급과 연동 끄기.
    private var friendRow: some View {
        VStack(spacing: 6) {
            HStack {
                Text("친구 연동").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: friends.myCode ?? "")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                // 예전 코드는 되살릴 수 없어서 한 번 더 물어봅니다.
                Button(confirmingRotate ? "정말 바꿀까요?" : "코드 새로 받기") {
                    if confirmingRotate {
                        Task { await friends.rotateCode() }
                        confirmingRotate = false
                    } else {
                        confirmingRotate = true
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("예전 코드는 못 쓰게 됩니다. 이미 연결된 친구는 그대로예요")

                Spacer()

                Button(confirmDisconnect ? "정말 끌까요?" : "연동 끄기", role: .destructive) {
                    if confirmDisconnect {
                        Task { await friends.disconnect() }
                        confirmDisconnect = false
                    } else {
                        confirmDisconnect = true
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("서버에서 내 기록과 친구 관계를 지워요. 내 맥의 기록은 그대로예요")
            }
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

    // 버전 표시 + Sparkle 업데이트 확인. 버튼을 누르면 Sparkle이 자체 창(버전·릴리스노트·설치+재시작)을 띄움.
    private var updateRow: some View {
        VStack(spacing: 6) {
            HStack {
                Text("버전").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("v\(appVersion)").font(.caption).foregroundStyle(.secondary)
            }

            Button {
                updater.checkForUpdates()
            } label: {
                Label("업데이트 확인", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!updater.canCheckForUpdates)
        }
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
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
