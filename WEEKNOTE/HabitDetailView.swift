import SwiftUI
import Charts
import Combine

@MainActor
final class HabitTimer: ObservableObject {
    static let shared = HabitTimer()
    @Published private(set) var habitID: UUID?
    @Published private(set) var startedAt: Date?
    @Published private(set) var accumulated: Double = 0
    private let defaults = UserDefaults.standard

    init() {
        habitID = defaults.string(forKey: "timer.habit").flatMap(UUID.init(uuidString:))
        let start = defaults.double(forKey: "timer.start")
        startedAt = start > 0 ? Date(timeIntervalSince1970: start) : nil
        accumulated = defaults.double(forKey: "timer.seconds")
        if habitID == nil { startedAt = nil; accumulated = 0 }
    }
    func elapsed(at date: Date = Date()) -> Double { max(0, accumulated + (startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)) }
    func start(_ id: UUID) { guard habitID == nil || habitID == id else { return }; habitID = id; startedAt = Date(); persist() }
    func pause() { accumulated = elapsed(); startedAt = nil; persist() }
    func reset() { habitID = nil; startedAt = nil; accumulated = 0; persist() }
    private func persist() { defaults.set(habitID?.uuidString, forKey: "timer.habit"); defaults.set(startedAt?.timeIntervalSince1970 ?? 0, forKey: "timer.start"); defaults.set(accumulated, forKey: "timer.seconds") }
}

private enum HabitPeriod: String, CaseIterable, Identifiable {
    case week = "Week", month = "Month", year = "Year"
    var id: String { rawValue }
}
private struct HabitBar: Identifiable { let date: Date; let minutes: Int; var id: Date { date } }

struct HabitDetailView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var timer = HabitTimer.shared
    var habitID: UUID
    @State private var period: HabitPeriod = .week
    @State private var reference = Date()
    @State private var logDate = Date()
    @State private var minutes = 15
    @State private var showEditor = false
    @State private var error: String?
    private var habit: Habit? { store.data.habits.first { $0.id == habitID } }
    private var days: [Date] {
        switch period {
        case .week: return CalendarSupport.weekDays(containing: reference)
        case .month: return CalendarSupport.monthDays(reference)
        case .year:
            let start = CalendarSupport.calendar.date(from: CalendarSupport.calendar.dateComponents([.year], from: reference))!
            let count = CalendarSupport.calendar.range(of: .day, in: .year, for: reference)?.count ?? 365
            return (0..<count).map { CalendarSupport.addingDays($0, to: start) }
        }
    }
    private var bars: [HabitBar] {
        if period == .year {
            let first = days.first ?? reference
            return (0..<12).map { month in
                let date = CalendarSupport.addingMonths(month, to: first)
                let total = CalendarSupport.monthDays(date).reduce(0) { $0 + store.habitMinutes(habitID, on: $1) }
                return HabitBar(date: date, minutes: total)
            }
        }
        return days.map { HabitBar(date: $0, minutes: store.habitMinutes(habitID, on: $0)) }
    }
    private var total: Int { bars.reduce(0) { $0 + $1.minutes } }
    private var activeDays: Int { days.filter { store.habitMinutes(habitID, on: $0) > 0 }.count }
    private var achievedDays: Int { days.filter { store.habitMinutes(habitID, on: $0) >= (habit?.goalMinutes ?? 1) }.count }
    private var periodLabel: String {
        switch period {
        case .week: return "\(CalendarSupport.formatted(days.first ?? reference, template: "Md")) – \(CalendarSupport.formatted(days.last ?? reference, template: "Md"))"
        case .month: return CalendarSupport.monthTitle(reference)
        case .year: return reference.formatted(.dateTime.year())
        }
    }

    var body: some View {
        NavigationStack {
            if let habit {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        HStack(spacing: 16) {
                            ProgressRing(progress: Double(store.habitMinutes(habitID, on: Date())) / Double(habit.goalMinutes), size: 72) { Image(systemName: habit.symbol).font(.system(size: 28, weight: .light)) }
                            VStack(alignment: .leading, spacing: 7) { Text(habit.name).font(.title2.bold()); Text("今日 \(store.habitMinutes(habitID, on: Date())) / \(habit.goalMinutes)分").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                        }
                        Picker("期間", selection: $period) { ForEach(HabitPeriod.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                        HStack {
                            Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }.accessibilityLabel("前の期間")
                            Spacer(); Text(periodLabel).font(.system(.subheadline, design: .monospaced)); Spacer()
                            Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }.accessibilityLabel("次の期間")
                        }
                        Chart {
                            ForEach(bars) { bar in
                                BarMark(x: .value("日付", bar.date, unit: period == .year ? .month : .day), y: .value("分", bar.minutes))
                                    .foregroundStyle(Color.primary.opacity(CalendarSupport.calendar.isDateInToday(bar.date) ? 0.9 : 0.55))
                                    .cornerRadius(4)
                            }
                            if period != .year { RuleMark(y: .value("目標", habit.goalMinutes)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Color.secondary.opacity(0.5)) }
                        }.chartXAxis { AxisMarks(values: .automatic(desiredCount: period == .week ? 7 : 6)) { _ in AxisValueLabel(format: period == .year ? .dateTime.month(.abbreviated) : .dateTime.day(), centered: true) } }
                            .chartYAxis { AxisMarks(position: .leading) }.frame(height: 170).accessibilityIdentifier("habit.chart")
                        HStack(spacing: 10) {
                            metric("合計", value: total, unit: "分")
                            metric("達成日", value: achievedDays, unit: "日")
                            metric("実行日の平均", value: activeDays == 0 ? 0 : total / activeDays, unit: "分")
                        }.padding(.vertical, 16).overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }.overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
                        VStack(alignment: .leading, spacing: 14) {
                            SectionCaption(title: "記録")
                            DatePicker("日付", selection: $logDate, in: ...Date(), displayedComponents: .date).font(.subheadline)
                            HStack {
                                Stepper("\(minutes)分", value: $minutes, in: 1...1440, step: 5).font(.subheadline)
                                Button("記録") { if store.addHabitLog(habitID: habitID, date: logDate, minutes: minutes) { error = nil } else { error = store.errorMessage } }
                                    .buttonStyle(.borderedProminent).tint(.primary).accessibilityIdentifier("habit.record")
                            }
                        }
                        timerControls
                        if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
                        recentLogs
                    }.padding(24)
                }.background(Theme.background).navigationTitle(habit.name).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                        ToolbarItem(placement: .topBarTrailing) { Button("編集") { showEditor = true } }
                    }
                    .sheet(isPresented: $showEditor) { HabitEditor(habit: habit).environmentObject(store) }
                    .onChange(of: store.data.habits) { _, habits in if !habits.contains(where: { $0.id == habitID }) { if timer.habitID == habitID { timer.reset() }; dismiss() } }
                    .accessibilityIdentifier("habit.detail")
            } else { ContentUnavailableView("習慣はありません", systemImage: "circle").toolbar { Button("閉じる") { dismiss() } } }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }

    private func metric(_ label: String, value: Int, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 3) { Text("\(value)").font(Theme.heading(30)); Text(unit).font(.caption).foregroundStyle(.secondary) }
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var timerControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionCaption(title: "タイマー")
            if let current = timer.habitID, current != habitID {
                Text("\(store.data.habits.first { $0.id == current }?.name ?? "別の習慣")を計測中").font(.subheadline).foregroundStyle(.secondary)
                Button("計測を取り消す", role: .destructive) { timer.reset() }
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = Int(timer.elapsed(at: context.date))
                    HStack(spacing: 16) {
                        Text(String(format: "%02d:%02d:%02d", elapsed / 3600, elapsed / 60 % 60, elapsed % 60)).font(.system(.title2, design: .monospaced)).monospacedDigit()
                        Spacer()
                        Button { if timer.startedAt != nil { timer.pause() } else { timer.start(habitID) } } label: { Image(systemName: timer.startedAt == nil ? "play.fill" : "pause.fill").frame(width: 36, height: 36) }.buttonStyle(.bordered).accessibilityLabel(timer.startedAt == nil ? "計測を開始" : "一時停止")
                    }
                }
                if timer.habitID == habitID {
                    HStack {
                        Button("終了して記録") {
                            let amount = max(1, Int(ceil(timer.elapsed() / 60)))
                            if store.addHabitLog(habitID: habitID, date: Date(), minutes: amount) { timer.reset(); error = nil } else { timer.pause(); error = store.errorMessage }
                        }.buttonStyle(.borderedProminent).tint(.primary)
                        Button("取り消す", role: .destructive) { timer.reset() }.font(.caption)
                    }
                    Text("1分未満を切り上げて記録します。").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var recentLogs: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionCaption(title: "最近の記録")
            let logs = store.data.logs.filter { $0.habitID == habitID }.sorted { $0.date > $1.date }.prefix(10)
            ForEach(Array(logs)) { log in
                HStack {
                    Text(log.date.formatted(.dateTime.month().day().weekday())).font(.subheadline)
                    Spacer(); Text("\(log.minutes)分").font(.system(.subheadline, design: .monospaced))
                    Button { _ = store.deleteHabitLog(log) } label: { Image(systemName: "trash").font(.caption).frame(width: 32, height: 32) }.foregroundStyle(.secondary).accessibilityLabel("\(log.date.formatted(.dateTime.month().day()))の\(log.minutes)分を削除")
                }.padding(.vertical, 7).overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
            }
            if logs.isEmpty { Text("記録はありません").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 14) }
        }
    }
    private func move(_ amount: Int) {
        switch period {
        case .week: reference = CalendarSupport.addingDays(amount * 7, to: reference)
        case .month: reference = CalendarSupport.addingMonths(amount, to: reference)
        case .year: reference = CalendarSupport.addingMonths(amount * 12, to: reference)
        }
    }
}
