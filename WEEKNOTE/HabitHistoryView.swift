import SwiftUI

enum HabitHistoryCalendar {
    static func yearDays(containing date: Date, calendar: Calendar = CalendarSupport.calendar) -> [Date] {
        guard let interval = calendar.dateInterval(of: .year, for: date),
              let count = calendar.range(of: .day, in: .year, for: date)?.count else { return [] }
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }
}

private struct HabitHistoryDay: Identifiable {
    let date: Date
    let minutes: Int
    var id: Date { date }
}

private struct HabitHistoryWeek: Identifiable {
    let start: Date
    let days: [HabitHistoryDay?]
    let monthLabel: String?
    var id: Date { start }
}

struct HabitHistoryView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var habitID: UUID? = nil
    var referenceDate = Date()
    var onSelectDate: ((Date) -> Void)? = nil
    @State private var selectedDate: Date?
    private let cellSize: CGFloat = 16
    private let cellSpacing: CGFloat = 4

    private var selectedHabits: [Habit] { store.data.habits.filter { habitID == nil || $0.id == habitID } }
    private var dailyGoal: Int { max(1, selectedHabits.reduce(0) { $0 + $1.goalMinutes }) }
    private func minutes(on date: Date) -> Int { selectedHabits.reduce(0) { $0 + store.habitMinutes($1.id, on: date) } }

    private var weeks: [HabitHistoryWeek] {
        let days = HabitHistoryCalendar.yearDays(containing: referenceDate)
        guard let first = days.first, let last = days.last else { return [] }
        let calendar = CalendarSupport.calendar
        let beginning = CalendarSupport.startOfWeek(first)
        let lastWeek = CalendarSupport.startOfWeek(last)
        let distance = calendar.dateComponents([.day], from: beginning, to: lastWeek).day ?? 0
        return stride(from: 0, through: distance, by: 7).map { offset in
            let start = CalendarSupport.addingDays(offset, to: beginning)
            let weekDays: [HabitHistoryDay?] = (0..<7).map { day in
                let date = CalendarSupport.addingDays(day, to: start)
                guard date >= first, date <= last else { return nil }
                return HabitHistoryDay(date: date, minutes: minutes(on: date))
            }
            let labelDate = weekDays.compactMap { $0?.date }.first { calendar.component(.day, from: $0) == 1 }
            return HabitHistoryWeek(start: start, days: weekDays,
                                    monthLabel: labelDate.map { CalendarSupport.formatted($0, template: "MMM") })
        }
    }

    private var initialWeek: Date {
        let year = CalendarSupport.calendar.component(.year, from: referenceDate)
        let currentYear = CalendarSupport.calendar.component(.year, from: Date())
        if year == currentYear { return CalendarSupport.startOfWeek(Date()) }
        let days = HabitHistoryCalendar.yearDays(containing: referenceDate)
        return CalendarSupport.startOfWeek(year < currentYear ? (days.last ?? referenceDate) : (days.first ?? referenceDate))
    }

    var body: some View {
        let grid = weeks
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionCaption(title: "年間の記録")
                Text(CalendarSupport.formatted(referenceDate, template: "yyyy"))
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 7) {
                VStack(spacing: cellSpacing) {
                    Color.clear.frame(width: 14, height: 18)
                    ForEach(0..<7) { weekday in
                        Text(weekday == 0 ? "月" : (weekday == 2 ? "水" : (weekday == 4 ? "金" : "")))
                            .font(.caption2).foregroundStyle(.secondary).frame(width: 14, height: cellSize)
                    }
                }
                ScrollViewReader { reader in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: cellSpacing) {
                            ForEach(grid) { week in
                                VStack(spacing: cellSpacing) {
                                    Text(week.monthLabel ?? "").font(.caption2).foregroundStyle(.secondary)
                                        .fixedSize().frame(width: cellSize, height: 18, alignment: .leading)
                                    ForEach(0..<7) { weekday in
                                        if let day = week.days[weekday] { dayCell(day) }
                                        else { Color.clear.frame(width: cellSize, height: cellSize).accessibilityHidden(true) }
                                    }
                                }.id(week.start)
                            }
                        }.padding(.trailing, 18).padding(.vertical, 2)
                    }.accessibilityIdentifier("habit.history.grid")
                        .onAppear { reader.scrollTo(initialWeek, anchor: .trailing) }
                        .onChange(of: CalendarSupport.calendar.component(.year, from: referenceDate)) { _, _ in
                            selectedDate = nil
                            reader.scrollTo(initialWeek, anchor: .trailing)
                        }
                }
            }
            HStack(spacing: 5) {
                if let date = selectedDate {
                    Text(CalendarSupport.formatted(date, template: "yyyyMdE"))
                    Text("\(minutes(on: date))分").monospacedDigit()
                } else { Text("日付をタップして記録を確認") }
                Spacer(minLength: 6)
            }.font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("habit.history.selection")
            HStack(spacing: 4) {
                Spacer()
                Text("少").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 3).fill(color(level: level)).frame(width: 12, height: 12)
                }
                Text("多").font(.caption2).foregroundStyle(.secondary)
            }.accessibilityElement(children: .ignore).accessibilityLabel("記録した分数が多い日ほど濃く表示")
        }.accessibilityIdentifier("habit.history")
    }

    private func dayCell(_ day: HabitHistoryDay) -> some View {
        let future = day.date > CalendarSupport.calendar.startOfDay(for: Date())
        let isSelected = selectedDate.map { CalendarSupport.isSameDay($0, day.date) } ?? false
        return Button {
            InteractionMotion.selectionFeedback()
            withAnimation(InteractionMotion.animation(reduceMotion: reduceMotion)) { selectedDate = day.date }
            onSelectDate?(day.date)
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(future ? Color.clear : color(level: level(minutes: day.minutes)))
                .overlay { RoundedRectangle(cornerRadius: 3).stroke(isSelected ? Theme.accent : Theme.line, lineWidth: isSelected ? 1.5 : 0.5) }
                .frame(width: cellSize, height: cellSize)
        }.buttonStyle(.plain).disabled(future)
            .accessibilityLabel("\(CalendarSupport.formatted(day.date, template: "yyyyMdE"))、\(future ? "未来の日付" : "\(day.minutes)分")")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityIdentifier("habit.history.day.\(CalendarSupport.dayKey(day.date))")
    }

    private func level(minutes: Int) -> Int {
        guard minutes > 0 else { return 0 }
        let ratio = Double(minutes) / Double(dailyGoal)
        if ratio < 0.25 { return 1 }
        if ratio < 0.5 { return 2 }
        if ratio < 1 { return 3 }
        return 4
    }

    private func color(level: Int) -> Color {
        level == 0 ? Theme.subtle : Theme.accent.opacity([0, 0.25, 0.45, 0.7, 1][level])
    }
}
