import SwiftUI
import AppKit

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
