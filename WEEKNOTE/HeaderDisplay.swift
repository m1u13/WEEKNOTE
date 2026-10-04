import SwiftUI

enum HeaderDisplayMode: String, Codable, CaseIterable, Identifiable {
    case weekNumber, deadline, yearEnd, elapsed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .weekNumber: return "週番号"
        case .deadline: return "目標までの日数"
        case .yearEnd: return "年末までの日数"
        case .elapsed: return "開始日からの日数"
        }
    }
}

/// Dates use local calendar-day keys so changing the device time zone does not move a goal date.
struct HeaderDisplayConfiguration: Codable, Equatable {
    var version = 1
    var mode: HeaderDisplayMode = .weekNumber
    var deadlineTitle = "目標"
    var deadlineDay: String
    var elapsedTitle = "目標"
    var startDay: String

    init(today: Date = Date()) {
        let key = CalendarSupport.dayKey(today)
        deadlineDay = key
        startDay = key
    }

    func sanitized(today: Date = Date()) -> Self {
        var result = self
        result.version = 1
        result.deadlineTitle = Self.cleanedTitle(deadlineTitle)
        result.elapsedTitle = Self.cleanedTitle(elapsedTitle)
        if Self.date(from: deadlineDay, calendar: CalendarSupport.calendar) == nil { result.deadlineDay = CalendarSupport.dayKey(today) }
        if Self.date(from: startDay, calendar: CalendarSupport.calendar) == nil { result.startDay = CalendarSupport.dayKey(today) }
        return result
    }

    static func date(from key: String, calendar: Calendar) -> Date? {
        guard key.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { return nil }
        let values = key.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3, (1900...2199).contains(values[0]), (1...12).contains(values[1]), (1...31).contains(values[2]),
              let date = calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2])) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == values[0], check.month == values[1], check.day == values[2] else { return nil }
        return date
    }

    private static func cleanedTitle(_ value: String) -> String {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "目標" : String(title.prefix(80))
    }
}

/// Display preferences are stored independently from the planner's task and habit backup.
enum HeaderDisplayPreference {
    static let storageKey = "header.display.configuration"
    static var defaultData: Data { encode(HeaderDisplayConfiguration()) }

    static func encode(_ configuration: HeaderDisplayConfiguration) -> Data {
        (try? JSONEncoder().encode(configuration.sanitized())) ?? Data()
    }

    static func decode(_ data: Data, today: Date = Date()) -> HeaderDisplayConfiguration {
        guard let value = try? JSONDecoder().decode(HeaderDisplayConfiguration.self, from: data), value.version == 1 else { return HeaderDisplayConfiguration(today: today) }
        return value.sanitized(today: today)
    }
}

struct HeaderDisplayReading: Equatable {
    var number: Int
    var value: String
    var unit: String?
    var label: String
    var detail: String?

    static func make(configuration: HeaderDisplayConfiguration, selectedDay: Date, today: Date = Date(), calendar: Calendar = CalendarSupport.calendar) -> Self {
        let day = calendar.startOfDay(for: today)
        switch configuration.mode {
        case .weekNumber:
            let week = calendar.component(.weekOfYear, from: selectedDay)
            return Self(number: week, value: String(format: "WEEK %02d", week), unit: nil, label: dateTitle(selectedDay, calendar: calendar, template: "yyyyMMMM"), detail: nil)
        case .deadline:
            let target = HeaderDisplayConfiguration.date(from: configuration.deadlineDay, calendar: calendar) ?? day
            let remaining = days(from: day, to: target, calendar: calendar)
            let name = configuration.deadlineTitle
            let label = remaining > 0 ? "\(name)まで" : remaining == 0 ? "\(name)当日" : "\(name)・目標日超過"
            return Self(number: abs(remaining), value: "\(abs(remaining))", unit: "日", label: label, detail: dateTitle(target, calendar: calendar, template: "yyyyMd"))
        case .yearEnd:
            let year = calendar.component(.year, from: day)
            let lastDay = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? day
            let remaining = max(0, days(from: day, to: lastDay, calendar: calendar))
            return Self(number: remaining, value: "\(remaining)", unit: "日", label: "\(year)年の終了まで", detail: nil)
        case .elapsed:
            let start = HeaderDisplayConfiguration.date(from: configuration.startDay, calendar: calendar) ?? day
            let elapsed = days(from: start, to: day, calendar: calendar)
            let label = elapsed < 0 ? "\(configuration.elapsedTitle)・開始まで" : "\(configuration.elapsedTitle)・開始から"
            return Self(number: abs(elapsed), value: "\(abs(elapsed))", unit: "日", label: label, detail: dateTitle(start, calendar: calendar, template: "yyyyMd"))
        }
    }

    private static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    private static func dateTitle(_ date: Date, calendar: Calendar, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

struct HeaderDisplaySummary: View {
    var selectedDay: Date
    @AppStorage(HeaderDisplayPreference.storageKey) private var storedConfiguration = HeaderDisplayPreference.defaultData

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HeaderDisplayReadingView(reading: .make(configuration: HeaderDisplayPreference.decode(storedConfiguration, today: context.date), selectedDay: selectedDay, today: context.date))
        }
    }
}

private struct HeaderDisplayReadingView: View {
    var reading: HeaderDisplayReading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(reading.label).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(reading.value).font(Theme.heading()).lineLimit(1).minimumScaleFactor(0.55)
                    .contentTransition(reduceMotion ? .identity : .numericText(value: Double(reading.number)))
                    .accessibilityIdentifier("week.heading")
                if let unit = reading.unit { Text(unit).font(.title3).foregroundStyle(.secondary) }
            }
            if let detail = reading.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: reading)
    }
}

struct HeaderDisplaySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(HeaderDisplayPreference.storageKey) private var storedConfiguration = HeaderDisplayPreference.defaultData
    @State private var draft = HeaderDisplayConfiguration()
    @State private var loaded = false
    @FocusState private var focusedTitle: Bool

    private var allowedDates: ClosedRange<Date> {
        let first = HeaderDisplayConfiguration.date(from: "1900-01-01", calendar: CalendarSupport.calendar)!
        let last = HeaderDisplayConfiguration.date(from: "2199-12-31", calendar: CalendarSupport.calendar)!
        return first...last
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HeaderDisplayReadingView(reading: .make(configuration: draft.sanitized(), selectedDay: Date()))
                        .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("header.preview")
                        .contentShape(Rectangle()).onTapGesture { focusedTitle = false }
                }
                Section {
                    ForEach(HeaderDisplayMode.allCases) { mode in
                        Button {
                            focusedTitle = false
                            InteractionMotion.selectionFeedback()
                            withAnimation(InteractionMotion.animation(reduceMotion: reduceMotion)) { draft.mode = mode }
                        } label: {
                            HStack {
                                Text(mode.title)
                                Spacer()
                                if draft.mode == mode { Image(systemName: "checkmark").fontWeight(.semibold) }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("header.mode.\(mode.rawValue)")
                            .accessibilityAddTraits(draft.mode == mode ? [.isSelected] : [])
                    }
                } footer: { Text("週番号は選択日、日数は今日を基準に表示します。目標日と開始日は0日です。") }
                if draft.mode == .deadline {
                    Section("目標") {
                        TextField("目標名", text: $draft.deadlineTitle).focused($focusedTitle).submitLabel(.done).accessibilityIdentifier("header.deadline.title")
                        DatePicker("目標日", selection: deadlineDate, in: allowedDates, displayedComponents: .date).accessibilityIdentifier("header.deadline.date")
                    }
                } else if draft.mode == .elapsed {
                    Section("開始日") {
                        TextField("目標名", text: $draft.elapsedTitle).focused($focusedTitle).submitLabel(.done).accessibilityIdentifier("header.elapsed.title")
                        DatePicker("開始日", selection: startDate, in: allowedDates, displayedComponents: .date).accessibilityIdentifier("header.elapsed.date")
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnBackgroundTap()
            .accessibilityElement(children: .contain)
            .navigationTitle("見出しの表示").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("header.settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { focusedTitle = false; storedConfiguration = HeaderDisplayPreference.encode(draft); dismiss() }
                        .fontWeight(.semibold).accessibilityIdentifier("header.save")
                }
            }
            .onAppear { if !loaded { draft = HeaderDisplayPreference.decode(storedConfiguration); loaded = true } }
            .onSubmit { focusedTitle = false }
            .onChange(of: draft.mode) { _, _ in focusedTitle = false }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }

    private var deadlineDate: Binding<Date> {
        Binding(get: { HeaderDisplayConfiguration.date(from: draft.deadlineDay, calendar: CalendarSupport.calendar) ?? Date() }, set: { focusedTitle = false; draft.deadlineDay = CalendarSupport.dayKey($0) })
    }

    private var startDate: Binding<Date> {
        Binding(get: { HeaderDisplayConfiguration.date(from: draft.startDay, calendar: CalendarSupport.calendar) ?? Date() }, set: { focusedTitle = false; draft.startDay = CalendarSupport.dayKey($0) })
    }
}
