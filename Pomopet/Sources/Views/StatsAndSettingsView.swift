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
        let minutes = dayStats[key]?.minutes ?? 0
        let highlighted = hovered == key || isToday
        return RoundedRectangle(cornerRadius: 4)
            .fill(color(for: minutes))
            .frame(height: 24)
            .overlay(
                Text("\(day)")
                    .font(.system(size: 10, weight: isToday ? .bold : .regular))
                    .foregroundStyle(minutes >= 75 ? Color.white : Color.primary.opacity(0.7))
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
        guard let stat = dayStats[key], stat.minutes > 0 else {
            return date + Text(verbatim: " · ") + Text("기록 없음")
        }
        return date + Text(verbatim: " · ") + minutesText(stat.minutes)
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

    // 강도 단계 색 (Less → More). 범례와 칸이 같은 색을 쓰도록 공유.
    static func intensityColors(tint: Color) -> [Color] {
        [.gray.opacity(0.15), tint.opacity(0.4), tint.opacity(0.6), tint.opacity(0.8), tint]
    }

    /// 집중 시간을 강도 4단계로. 25분(한 세션 기본 길이)을 한 칸으로 봅니다.
    private func color(for minutes: Int) -> Color {
        let level = minutes <= 0 ? 0 : min(4, (minutes - 1) / 25 + 1)
        return Self.intensityColors(tint: tint)[level]
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
    @ObservedObject var workWatcher: WorkAppWatcher
    @State private var focus: Double
    @State private var breakV: Double
    @State private var didSave = false
    @State private var saveMessageToken = 0
    @State private var confirmingAppRemoval: String?   // 지울지 물어보는 중인 앱의 bundleID
    @State private var pendingCharacter: NSImage?      // 미리보기 중인 새 캐릭터

    init(controller: PomopetController, updater: UpdaterManager, lang: LanguageManager,
         workWatcher: WorkAppWatcher) {
        self.controller = controller
        self.updater = updater
        self.lang = lang
        self.workWatcher = workWatcher
        _focus = State(initialValue: Double(controller.settings.focusMinutes))
        _breakV = State(initialValue: Double(controller.settings.breakMinutes))
    }

    var body: some View {
        // 항목마다 제목과 구분선을 둡니다.
        // 예전에는 "캐릭터 바꾸기" 와 "저장" 이 같은 줄에 나란히 있어서,
        // 저장이 무엇을 저장하는 건지(캐릭터인지 타이머인지) 알기 어려웠습니다.
        VStack(spacing: 14) {
            timerSection

            Divider()

            characterSection

            Divider()

            autoStartRow

            Divider()

            languageRow

            Divider()

            updateRow

            Button("Pomopet 종료") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }

    // 타이머 길이 — 이 항목의 저장 버튼은 위 두 슬라이더만 저장합니다.
    private var timerSection: some View {
        VStack(spacing: 8) {
            sectionTitle("타이머")

            sliderRow(title: "집중", value: $focus, range: 5...60, unit: "분")
            sliderRow(title: "휴식", value: $breakV, range: 1...30, unit: "분")

            HStack {
                Label("저장되었습니다", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .opacity(didSave ? 1 : 0)
                    .animation(.easeInOut(duration: didSave ? 0.15 : 0.5), value: didSave)

                Spacer()

                Button("타이머 저장") {
                    var s = controller.settings
                    s.focusMinutes = Int(focus)
                    s.breakMinutes = Int(breakV)
                    controller.updateSettings(s)
                    showSavedMessage()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!timerChanged)
            }
        }
        // 값을 수정하면 저장 메시지를 숨겨 현재 상태를 반영
        .onChange(of: focus) { didSave = false }
        .onChange(of: breakV) { didSave = false }
    }

    /// 슬라이더를 건드리지 않았으면 저장할 게 없습니다.
    private var timerChanged: Bool {
        Int(focus) != controller.settings.focusMinutes || Int(breakV) != controller.settings.breakMinutes
    }

    // 캐릭터 — 고르는 즉시 바뀌므로 따로 저장할 게 없습니다.
    @ViewBuilder
    private var characterSection: some View {
        VStack(spacing: 6) {
            sectionTitle("캐릭터")

            if let pending = pendingCharacter {
                CharacterPreview(
                    image: pending,
                    onConfirm: { final in
                        controller.changeCharacter(final)
                        pendingCharacter = nil
                    },
                    onRetry: { pendingCharacter = pickImageFile() ?? pending }
                )
                // 다른 이미지를 고르면 미리보기를 새로 시작합니다.
                .id(ObjectIdentifier(pending))
            } else {
                Button {
                    pendingCharacter = pickImageFile()
                } label: {
                    Label("캐릭터 바꾸기", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Text("바꿔도 연속 기록과 집중 시간은 그대로예요")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 항목 제목.
    private func sectionTitle(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 작업 앱을 켜면 집중을 시작해주는 기능.
    private var autoStartRow: some View {
        VStack(spacing: 6) {
            sectionTitle("작업 시작")

            Toggle(isOn: Binding(
                get: { workWatcher.settings.enabled },
                set: { workWatcher.settings.enabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("작업 시작하면 자동으로").font(.callout)
                    Text("정해둔 앱을 켜면 3초 뒤 집중이 시작돼요")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            if workWatcher.settings.enabled {
                VStack(spacing: Self.appRowSpacing) {
                    // 4개까지는 그대로 다 보이고, 그보다 많으면 스크롤됩니다.
                    // 높이를 줄 수에 딱 맞추지 않고 한 줄이 반쯤 걸치게 두어,
                    // 아래에 더 있다는 걸 잘린 모습으로 알 수 있게 합니다.
                    if workWatcher.settings.apps.count > Self.appRowsWithoutScroll {
                        ScrollView { appRows }
                            .frame(height: Self.appListHeight)
                    } else {
                        appRows
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

    /// 스크롤 없이 다 보여줄 작업 앱 수.
    private static let appRowsWithoutScroll = 4
    /// 한 줄 높이(아이콘 14 + 위아래 여백)와 줄 사이 간격.
    private static let appRowHeight: CGFloat = 20
    private static let appRowSpacing: CGFloat = 4
    /// 네 줄 반이 보이는 높이. 다섯 번째가 반쯤 잘려 더 있다는 게 드러납니다.
    private static let appListHeight: CGFloat = appRowHeight * 4.5 + appRowSpacing * 4

    private var appRows: some View {
        VStack(spacing: Self.appRowSpacing) {
            ForEach(workWatcher.settings.apps) { app in
                HStack(spacing: 6) {
                    if let icon = app.icon {
                        Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                    }
                    Text(verbatim: app.name).font(.caption).lineLimit(1)

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
                .frame(height: Self.appRowHeight)
            }
        }
    }

    // 친구 연동을 켠 뒤의 관리 항목 — 코드 재발급과 연동 끄기.
    // 언어 전환: 시스템 언어와 무관하게 한국어/영어를 버튼으로 직접 선택.
    private var languageRow: some View {
        HStack {
            Text("언어").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
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
                Text("버전").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
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

    /// 저장 직후 "저장되었습니다" 를 잠깐 띄웠다가 스스로 사라지게 합니다.
    /// 저장 버튼은 값을 다시 건드리기 전까지 비활성이라, 이 메시지가 유일한 확인 신호입니다.
    private func showSavedMessage() {
        saveMessageToken += 1
        let token = saveMessageToken
        didSave = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            // 그사이 다시 저장했으면 새 타이머에 맡기고 여기서는 끄지 않습니다.
            if token == saveMessageToken { didSave = false }
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
