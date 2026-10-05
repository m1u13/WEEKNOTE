import SwiftUI

enum AppTab: Hashable { case week, calendar, progress }
enum EditorSheet: Identifiable {
    case task(PlannerTask, Bool), habit(Habit), habitEditor(Habit?), list(PlannerList?), link(SavedLink?), headerDisplay
    var id: String {
        switch self {
        case .task(let task, _): return "task-\(task.id)"
        case .habit(let habit): return "habit-\(habit.id)"
        case .habitEditor(let habit): return "edit-habit-\(habit?.id.uuidString ?? "new")"
        case .list(let list): return "list-\(list?.id.uuidString ?? "new")"
        case .link(let link): return "link-\(link?.id.uuidString ?? "new")"
        case .headerDisplay: return "header-display"
        }
    }
}

private enum ManagementScreen: String, Identifiable {
    case lists, settings
    var id: String { rawValue }
}

private struct EditorDestination: View {
    let destination: EditorSheet
    var body: some View {
        switch destination {
        case .task(let task, let isNew): TaskEditor(task: task, isNew: isNew)
        case .habit(let habit): HabitDetailView(habitID: habit.id)
        case .habitEditor(let habit): HabitEditor(habit: habit)
        case .list(let list): ListEditor(list: list)
        case .link(let link): LinkEditor(link: link)
        case .headerDisplay: HeaderDisplaySettingsView()
        }
    }
}

private struct ManagementPanel: View {
    @Environment(\.dismiss) private var dismiss
    let screen: ManagementScreen
    @State private var sheet: EditorSheet?

    var body: some View {
        NavigationStack {
            Group {
                switch screen {
                case .lists: ListsView { sheet = $0 }
                case .settings: SettingsView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.accessibilityIdentifier("management.close")
                }
            }
        }
        .sheet(item: $sheet) { EditorDestination(destination: $0) }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: AppTab = .week
    @State private var selectedDay = Date()
    @State private var month = Date()
    @State private var sheet: EditorSheet?
    @State private var management: ManagementScreen?
    @State private var search = ""
    @State private var taskFilter = 0
    @State private var monthDirection = 1

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { weeklyView.toolbar { ToolbarItem(placement: .topBarTrailing) { managementMenu } } }.tabItem { Label("今週", systemImage: "checklist") }.tag(AppTab.week)
            NavigationStack { calendarView.toolbar { ToolbarItem(placement: .topBarTrailing) { managementMenu } } }.tabItem { Label("カレンダー", systemImage: "calendar") }.tag(AppTab.calendar)
            NavigationStack { ProgressViewScreen(selectedDay: $selectedDay, showHabit: { sheet = .habit($0) }, editHabit: { sheet = .habitEditor($0) }).toolbar { ToolbarItem(placement: .topBarTrailing) { managementMenu } } }.tabItem { Label("進捗", systemImage: "chart.bar") }.tag(AppTab.progress)
        }
        .tint(Theme.accent)
        .sheet(item: $sheet) { EditorDestination(destination: $0) }
        .sheet(item: $management) { ManagementPanel(screen: $0) }
    }

    private var managementMenu: some View {
        Menu {
            Button { management = .lists } label: { Label("リスト", systemImage: "folder") }
            Button { management = .settings } label: { Label("設定", systemImage: "slider.horizontal.3") }
        }
        label: { Image(systemName: "ellipsis.circle") }
        .accessibilityLabel("リストと設定").accessibilityIdentifier("navigation.menu")
    }

    private var selectedTasks: [PlannerTask] { store.tasks(on: selectedDay, kind: .todo).filter(matches) }
    private var undatedTasks: [PlannerTask] { store.data.tasks.filter { $0.kind == .todo && $0.date == nil }.filter(matches) }
    private func matches(_ task: PlannerTask) -> Bool {
        (search.isEmpty || task.title.localizedCaseInsensitiveContains(search) || task.notes.localizedCaseInsensitiveContains(search)) && (taskFilter == 0 || (taskFilter == 1 ? !task.isCompleted : task.isCompleted))
    }

    private var weeklyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                DateRibbon(selectedDay: $selectedDay)
                habits
                HStack {
                    Text(selectedDay.formatted(.dateTime.month().day().weekday())).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Picker("表示", selection: $taskFilter) { Text("すべて").tag(0); Text("未完了").tag(1); Text("完了済み").tag(2) }
                    } label: { Image(systemName: "line.3.horizontal.decrease").frame(width: 36, height: 32) }.accessibilityLabel("表示を絞り込む")
                }
                agendaSection(tasks: store.tasks(on: selectedDay, kind: .event).filter(matches) + selectedTasks)
                if !undatedTasks.isEmpty {
                    DisclosureGroup {
                        ForEach(undatedTasks) { task in TaskRow(task: task) { sheet = .task(task, false) } }
                    } label: {
                        HStack { Text("日付なし"); Spacer(); Text("\(undatedTasks.count)").foregroundStyle(.secondary).monospacedDigit() }
                    }
                }
            }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 22)
        }
        .accessibilityIdentifier("screen.week")
        .background(Theme.background)
        .navigationTitle("WEEKNOTE").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { addBar(kind: .todo) }
        .searchable(text: $search, prompt: "タスクを検索")
        .scrollDismissesKeyboard(.interactively)
        .animation(InteractionMotion.animation(reduceMotion: reduceMotion), value: taskFilter)
    }

    private func agendaSection(tasks: [PlannerTask]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionCaption(title: "予定とタスク", count: tasks.count)
            if tasks.isEmpty { Text("予定・タスクはありません").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 16) }
            ForEach(tasks) { task in
                if task.kind == .event { EventRow(task: task) { sheet = .task(task, false) } }
                else { TaskRow(task: task) { sheet = .task(task, false) } }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HeaderDisplaySummary(selectedDay: selectedDay)
                .contentShape(Rectangle()).onTapGesture { sheet = .headerDisplay }
                .accessibilityAction(named: Text("見出しの表示を変更")) { sheet = .headerDisplay }
                .contextMenu { Button { sheet = .headerDisplay } label: { Label("見出しの表示を変更", systemImage: "calendar.badge.clock") } }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 18) {
                Button("今日") { withAnimation(InteractionMotion.animation(reduceMotion: reduceMotion)) { selectedDay = Date() } }
                Button { sheet = .headerDisplay } label: { Label("表示", systemImage: "chevron.down").labelStyle(.titleAndIcon) }
                    .accessibilityIdentifier("header.configure")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    private var habits: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { SectionCaption(title: "HABITS"); Button { sheet = .habitEditor(nil) } label: { Image(systemName: "plus") }.accessibilityLabel("習慣を追加").accessibilityIdentifier("habit.add") }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(store.data.habits) { habit in
                        let minutes = store.habitMinutes(habit, on: selectedDay)
                        Button { sheet = .habit(habit) } label: {
                            VStack(spacing: 9) {
                                ProgressRing(progress: Double(minutes) / Double(habit.goalMinutes)) { Image(systemName: habit.symbol).font(.system(size: 25, weight: .light)) }
                                Text(habit.name).font(.caption).lineLimit(1)
                                Text("\(minutes) / \(habit.goalMinutes)分").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain).contentShape(Rectangle()).accessibilityIdentifier("habit.\(habit.name)")
                            .modifier(HabitContextActions(habit: habit, open: { sheet = .habit(habit) }, edit: { sheet = .habitEditor(habit) }))
                    }
                    Button { sheet = .habitEditor(nil) } label: {
                        VStack(spacing: 9) { Circle().stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(width: 64, height: 64).overlay { Image(systemName: "plus").foregroundStyle(.secondary) }; Text("追加").font(.caption).foregroundStyle(.secondary) }
                    }.buttonStyle(.plain).accessibilityLabel("新しい習慣")
                }.padding(.vertical, 3)
            }
        }
    }

    private func addBar(kind: TaskKind) -> some View {
        Button {
            var date = selectedDay
            if kind == .event {
                let time = CalendarSupport.calendar.dateComponents([.hour, .minute], from: Date())
                date = CalendarSupport.calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: selectedDay) ?? selectedDay
            }
            sheet = .task(PlannerTask(title: "", date: date, kind: kind), true)
        } label: {
            HStack { Image(systemName: "plus"); Text(kind == .todo ? "タスクを追加" : "予定を追加"); Spacer() }
                .font(.subheadline).padding(17).background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14)).overlay { RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.25), lineWidth: 0.5) }
        }.buttonStyle(PressFeedbackStyle()).padding(.horizontal, 24).padding(.vertical, 12).background(Theme.background.opacity(0.85)).accessibilityIdentifier(kind == .todo ? "task.add" : "event.add")
    }

    private var calendarView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack {
                    Text(month.formatted(.dateTime.year().month())).font(.title2.bold()).contentTransition(.numericText()).accessibilityIdentifier("calendar.monthTitle")
                        .contentShape(Rectangle()).contextMenu {
                            Button("前の月") { moveMonth(-1) }
                            Button("次の月") { moveMonth(1) }
                        }
                    Spacer()
                }
                ZStack {
                    MonthGrid(month: month, selectedDay: $selectedDay, addItem: { day, kind in
                        selectedDay = day
                        sheet = .task(PlannerTask(title: "", date: day, kind: kind), true)
                    })
                    .id(CalendarSupport.monthTitle(month))
                    .transition(InteractionMotion.pageTransition(direction: monthDirection, reduceMotion: reduceMotion))
                }.clipped().horizontalPageSwipe(onChange: moveMonth)
                    .accessibilityAction(named: Text("次の月")) { moveMonth(1) }
                    .accessibilityAction(named: Text("前の月")) { moveMonth(-1) }
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedDay.formatted(.dateTime.month().day().weekday())).font(.headline)
                    if let holiday = HolidayCalendar.shared.name(for: selectedDay) { Label(holiday, systemImage: "flag").font(.subheadline).foregroundStyle(Theme.holiday) }
                }
                agendaSection(tasks: store.tasks(on: selectedDay, kind: .event) + store.tasks(on: selectedDay, kind: .todo))
                Text(HolidayCalendar.shared.coverageText).font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.background(Theme.background).navigationTitle("カレンダー").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("今日") { withAnimation { month = Date(); selectedDay = Date() } } } }
            .safeAreaInset(edge: .bottom, spacing: 0) { addBar(kind: .event) }
    }

    private func moveMonth(_ offset: Int) {
        monthDirection = offset
        withAnimation(InteractionMotion.animation(reduceMotion: reduceMotion)) { month = CalendarSupport.addingMonths(offset, to: month) }
    }
}

struct DateRibbon: View {
    @Binding var selectedDay: Date
    @State private var anchor = CalendarSupport.startOfWeek(Date())
    private var days: [Date] { (-14..<21).map { CalendarSupport.addingDays($0, to: anchor) } }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(days, id: \.self) { day in
                        let selected = CalendarSupport.calendar.isDate(day, inSameDayAs: selectedDay)
                        let holiday = HolidayCalendar.shared.name(for: day)
                        Button { withAnimation { selectedDay = day } } label: {
                            VStack(spacing: 5) {
                                Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption2)
                                Text(day.formatted(.dateTime.day())).font(.title3.weight(selected ? .bold : .regular))
                                Circle().fill(CalendarSupport.calendar.isDateInToday(day) ? Theme.accent : .clear).frame(width: 3, height: 3)
                            }.foregroundStyle(holiday != nil || CalendarSupport.calendar.component(.weekday, from: day) == 1 ? Theme.holiday : (selected ? Theme.accent : .primary))
                                .frame(width: 46, height: 72).background(selected ? Theme.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).id(CalendarSupport.dayKey(day)).accessibilityLabel(day.formatted(.dateTime.month().day().weekday()) + (holiday.map { " \($0)" } ?? ""))
                            .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }.padding(.vertical, 4)
            }.accessibilityIdentifier("date.ribbon")
                .onAppear {
                    if !days.contains(where: { CalendarSupport.isSameDay($0, selectedDay) }) { anchor = CalendarSupport.startOfWeek(selectedDay) }
                    else { proxy.scrollTo(CalendarSupport.dayKey(selectedDay), anchor: .center) }
                }
                .onChange(of: selectedDay) { _, date in
                    let offset = CalendarSupport.calendar.dateComponents([.day], from: anchor, to: date).day ?? 0
                    if offset < -7 || offset > 14 { anchor = CalendarSupport.startOfWeek(date) }
                    else { withAnimation { proxy.scrollTo(CalendarSupport.dayKey(date), anchor: .center) } }
                }
                .onChange(of: anchor) { _, _ in withAnimation { proxy.scrollTo(CalendarSupport.dayKey(selectedDay), anchor: .center) } }
        }.overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5).offset(y: 9) }
    }
}

struct MonthGrid: View {
    @EnvironmentObject private var store: PlannerStore
    var month: Date
    @Binding var selectedDay: Date
    var addItem: ((Date, TaskKind) -> Void)? = nil
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private var dates: [Date] {
        let first = CalendarSupport.calendar.date(from: CalendarSupport.calendar.dateComponents([.year, .month], from: month))!
        let start = CalendarSupport.startOfWeek(first)
        return (0..<42).map { CalendarSupport.addingDays($0, to: start) }
    }
    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(["月", "火", "水", "木", "金", "土", "日"].enumerated()), id: \.offset) { index, day in Text(day).font(.caption).foregroundStyle(index == 6 ? Theme.holiday : .secondary).frame(maxWidth: .infinity).padding(.bottom, 5) }
            ForEach(dates, id: \.self) { date in
                let holiday = HolidayCalendar.shared.name(for: date)
                let sameMonth = CalendarSupport.calendar.component(.month, from: date) == CalendarSupport.calendar.component(.month, from: month)
                let selected = CalendarSupport.calendar.isDate(date, inSameDayAs: selectedDay)
                let hasTasks = !store.tasks(on: date).isEmpty
                Button { selectedDay = date } label: {
                    VStack(spacing: 3) {
                        Text(date.formatted(.dateTime.day())).font(.body.weight(selected ? .bold : .regular))
                        Text(holiday ?? " ").font(.system(size: 8)).lineLimit(1).minimumScaleFactor(0.7).frame(height: 12)
                        Circle().fill(hasTasks ? Theme.accent : .clear).frame(width: 3, height: 3)
                    }.foregroundStyle(holiday != nil || CalendarSupport.calendar.component(.weekday, from: date) == 1 ? Theme.holiday : (selected ? Theme.accent : .primary))
                        .opacity(sameMonth ? 1 : 0.3).frame(maxWidth: .infinity).frame(minHeight: 51)
                        .background(selected ? Theme.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .overlay { RoundedRectangle(cornerRadius: 9).stroke(CalendarSupport.calendar.isDateInToday(date) ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1) }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(date.formatted(.dateTime.month().day().weekday()) + (holiday.map { " \($0)" } ?? ""))
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .contextMenu {
                        if let addItem {
                            Button { addItem(date, .todo) } label: { Label("タスクを追加", systemImage: "plus") }
                            Button { addItem(date, .event) } label: { Label("予定を追加", systemImage: "calendar.badge.plus") }
                        }
                    }
            }
        }.frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("calendar.month")
    }
}

struct ProgressViewScreen: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedDay: Date
    var showHabit: (Habit) -> Void
    var editHabit: (Habit) -> Void
    @State private var weekDirection = 1
    private var days: [Date] { CalendarSupport.weekDays(containing: selectedDay) }
    private var tasks: [PlannerTask] { store.data.tasks.filter { task in task.date.map { d in days.contains { CalendarSupport.calendar.isDate($0, inSameDayAs: d) } } ?? true } }
    private var done: Int { tasks.filter(\.isCompleted).count }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                DateRibbon(selectedDay: $selectedDay)
                ZStack {
                  VStack(alignment: .leading, spacing: 8) {
                    SectionCaption(title: "週間の完了率")
                    Text("\(CalendarSupport.formatted(days.first ?? selectedDay, template: "Md")) – \(CalendarSupport.formatted(days.last ?? selectedDay, template: "Md"))")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).accessibilityIdentifier("progress.weekLabel")
                    HStack(alignment: .firstTextBaseline, spacing: 4) { Text("\(tasks.isEmpty ? 0 : Int(Double(done) / Double(tasks.count) * 100))").font(Theme.heading(76)).contentTransition(.numericText()); Text("%").font(Theme.heading(34)).foregroundStyle(.secondary) }
                    Text("\(tasks.count)件中 \(done)件完了").font(.subheadline).foregroundStyle(.secondary)
                    SwiftUI.ProgressView(value: tasks.isEmpty ? 0 : Double(done) / Double(tasks.count)).tint(Theme.accent)
                  }.frame(maxWidth: .infinity, alignment: .leading)
                    .id(CalendarSupport.dayKey(CalendarSupport.startOfWeek(selectedDay)))
                    .transition(InteractionMotion.pageTransition(direction: weekDirection, reduceMotion: reduceMotion))
                }.clipped().contentShape(Rectangle()).horizontalPageSwipe { offset in moveWeek(offset) }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("progress.week")
                    .accessibilityAction(named: Text("次の週")) { moveWeek(1) }
                    .accessibilityAction(named: Text("前の週")) { moveWeek(-1) }
                    .contextMenu {
                        Button("前の週") { moveWeek(-1) }
                        Button("次の週") { moveWeek(1) }
                        Button("今週") { withAnimation(InteractionMotion.animation(reduceMotion: reduceMotion)) { selectedDay = Date() } }
                    }
                HabitHistoryView(referenceDate: selectedDay, onSelectDate: { selectedDay = $0 })
                VStack(alignment: .leading, spacing: 14) {
                    SectionCaption(title: "習慣")
                    ForEach(store.data.habits) { habit in
                        let total = days.reduce(0) { $0 + store.habitMinutes(habit, on: $1) }
                        Button { showHabit(habit) } label: {
                            HStack(spacing: 14) { Image(systemName: habit.symbol).foregroundStyle(Theme.accent).frame(width: 28); Text(habit.name); Spacer(); Text("\(total)分").font(.system(.body, design: .monospaced)); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 15)
                        }.buttonStyle(.plain).overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
                            .modifier(HabitContextActions(habit: habit, open: { showHabit(habit) }, edit: { editHabit(habit) }))
                    }
                }
            }.padding(24)
        }.background(Theme.background).navigationTitle("進捗").navigationBarTitleDisplayMode(.inline)
    }
    private func moveWeek(_ offset: Int) {
        weekDirection = offset
        withAnimation(InteractionMotion.animation(reduceMotion: reduceMotion)) { selectedDay = CalendarSupport.addingDays(offset * 7, to: selectedDay) }
    }
}

struct ListsView: View {
    @EnvironmentObject private var store: PlannerStore
    var showSheet: (EditorSheet) -> Void
    var body: some View {
        List {
            Section {
                ForEach(store.data.lists) { list in
                    NavigationLink { ListDetailView(listID: list.id, showSheet: showSheet) } label: {
                        HStack { Label(list.name, systemImage: list.symbol); Spacer(); Text("\(store.data.tasks.filter { $0.listID == list.id && !$0.isCompleted }.count)").font(.caption).foregroundStyle(.secondary) }
                    }
                    .accessibilityIdentifier("list.item.\(list.name)")
                    .modifier(ListContextActions(list: list, edit: { showSheet(.list(list)) }, addTask: { showSheet(.task(PlannerTask(title: "", listID: list.id), true)) }))
                }
                Button { showSheet(.list(nil)) } label: { Label("リストを追加", systemImage: "plus") }.accessibilityIdentifier("list.add")
            }
            Section {
                NavigationLink { SavedLinksView(listID: nil, showSheet: showSheet) } label: { Label("保存したリンク", systemImage: "link") }
                NavigationLink { RepeatingTasksView(showSheet: showSheet) } label: { Label("繰り返し", systemImage: "repeat") }
            }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("リスト")
    }
}

struct ListDetailView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    var listID: UUID
    var showSheet: (EditorSheet) -> Void
    private var list: PlannerList? { store.data.lists.first { $0.id == listID } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 0) {
                    let tasks = store.data.tasks.filter { $0.listID == listID }
                    if tasks.isEmpty { Text("項目はありません").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(tasks) { task in
                        if task.kind == .event { EventRow(task: task) { showSheet(.task(task, false)) } }
                        else { TaskRow(task: task, showDate: true) { showSheet(.task(task, false)) } }
                    }
                    Button { showSheet(.task(PlannerTask(title: "", listID: listID), true)) } label: { Label("タスクを追加", systemImage: "plus").font(.subheadline).padding(.vertical, 16) }
                }
                SavedLinksSection(listID: listID, showSheet: showSheet)
            }.padding(24)
        }.background(Theme.background).navigationTitle(list?.name ?? "リスト")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showSheet(.list(list)) } label: { Image(systemName: "ellipsis") }.accessibilityLabel("リストを編集") } }
            .onChange(of: store.data.lists) { _, lists in
                if !lists.contains(where: { $0.id == listID }) { dismiss() }
            }
    }
}

struct RepeatingTasksView: View {
    @EnvironmentObject private var store: PlannerStore
    var showSheet: (EditorSheet) -> Void
    var body: some View {
        ScrollView { VStack(spacing: 0) { ForEach(store.data.tasks.filter(\.repeatsDaily)) { task in TaskRow(task: task, showDate: true) { showSheet(.task(task, false)) } } }.padding(24) }.background(Theme.background).navigationTitle("繰り返し")
    }
}

struct SavedLinksView: View {
    var listID: UUID?
    var showSheet: (EditorSheet) -> Void
    var body: some View { ScrollView { SavedLinksSection(listID: listID, showSheet: showSheet).padding(24) }.background(Theme.background).navigationTitle("保存したリンク") }
}

struct SavedLinksSection: View {
    @EnvironmentObject private var store: PlannerStore
    var listID: UUID?
    var showSheet: (EditorSheet) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if store.data.links.contains(where: { listID == nil || $0.listID == listID }) { SectionCaption(title: "リンク") }
            ForEach(store.data.links.filter { listID == nil || $0.listID == listID }) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if let url = URL(string: item.url) { Link(destination: url) { Label(item.title, systemImage: "link").font(.body) } }
                        Spacer()
                        Button { showSheet(.link(item)) } label: { Image(systemName: "ellipsis") }.accessibilityLabel("\(item.title)を編集")
                    }
                    Text(URL(string: item.url)?.host ?? item.url).font(.caption).foregroundStyle(.secondary)
                    if !item.notes.isEmpty { Text(item.notes).font(.subheadline).foregroundStyle(.secondary) }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Theme.subtle, in: RoundedRectangle(cornerRadius: 12))
                    .modifier(LinkContextActions(link: item, edit: { showSheet(.link(item)) }))
            }
            Button { showSheet(.link(listID.map { SavedLink(title: "", url: "", listID: $0) })) } label: { Label("リンクを追加", systemImage: "plus").font(.subheadline) }
        }
    }
}
