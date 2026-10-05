import SwiftUI

struct TaskEditor: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlannerTask
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var showDelete = false
    @State private var error: String?
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case title, location, notes }
    let isNew: Bool

    init(task: PlannerTask, isNew: Bool) {
        _draft = State(initialValue: task)
        _hasDate = State(initialValue: task.date != nil)
        _date = State(initialValue: task.date ?? Date())
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("タイトル", text: $draft.title, axis: .vertical).lineLimit(1...4).focused($focusedField, equals: .title).accessibilityIdentifier("task.title")
                    Picker("種類", selection: $draft.kind) { ForEach(TaskKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier("task.kind")
                    if isNew {
                        Button("タイトルから日時を入力") {
                            let parsed = CalendarSupport.parseQuickEntry(draft.title, relativeTo: Date())
                            if let parsedDate = parsed.date { date = parsedDate; hasDate = true; draft.title = parsed.title; if parsed.hasTime { draft.kind = .event } }
                        }.font(.caption)
                        Text("例：明日15時に打ち合わせ").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("日時") {
                    if draft.kind == .todo { Toggle("日付を指定", isOn: $hasDate) }
                    if hasDate || draft.kind == .event {
                        DatePicker(draft.kind == .event ? "開始" : "日付", selection: $date, displayedComponents: draft.kind == .event ? [.date, .hourAndMinute] : [.date])
                        if draft.kind == .event {
                            Stepper("所要時間 \(draft.durationMinutes)分", value: $draft.durationMinutes, in: 1...1440, step: 5)
                            TextField("場所", text: $draft.location).focused($focusedField, equals: .location).accessibilityIdentifier("task.location")
                        }
                    }
                    Toggle("毎日繰り返す", isOn: $draft.repeatsDaily)
                }
                Section {
                    Picker("リスト", selection: $draft.listID) { ForEach(store.data.lists) { Text($0.name).tag($0.id) } }
                    Toggle("優先", isOn: $draft.isPriority)
                    TextField("メモ", text: $draft.notes, axis: .vertical).lineLimit(3...10).focused($focusedField, equals: .notes).accessibilityIdentifier("task.notes")
                }
                if !isNew {
                    Section {
                        Toggle("完了", isOn: $draft.isCompleted)
                        if let completed = draft.completedAt {
                            LabeledContent(draft.completionDateOnly ? "完了日（時刻不明）" : "完了日時", value: draft.completionDateOnly ? completed.formatted(.dateTime.month().day()) : completed.formatted(.dateTime.month().day().hour().minute()))
                        }
                        Button("削除", role: .destructive) { showDelete = true }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.subheadline) } }
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnBackgroundTap()
            .accessibilityElement(children: .contain)
            .navigationTitle(isNew ? (draft.kind == .event ? "予定を追加" : "タスクを追加") : "編集").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).bold().accessibilityIdentifier("editor.save") }
            }
            .confirmationDialog("この項目を削除しますか？", isPresented: $showDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) { if store.deleteTask(draft) { dismiss() } else { error = store.errorMessage } }
                Button("キャンセル", role: .cancel) { showDelete = false }
            }
            .onChange(of: draft.kind) { _, value in if value == .event { hasDate = true } }
            .onChange(of: draft.isCompleted) { _, _ in draft.completedAt = nil; draft.completionDateOnly = false }
            .accessibilityIdentifier("editor.task")
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }

    private func save() {
        draft.date = hasDate || draft.kind == .event ? date : nil
        if draft.isCompleted { draft.completedAt = draft.completedAt ?? Date() } else { draft.completedAt = nil }
        if store.saveTask(draft) { dismiss() } else { error = store.errorMessage }
    }
}

struct HabitEditor: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: Habit
    @State private var error: String?
    @State private var showDelete = false
    @FocusState private var nameFocused: Bool
    private let isNew: Bool
    init(habit: Habit?) { _draft = State(initialValue: habit ?? Habit(name: "")); isNew = habit == nil }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        EditorTitleRow(symbol: draft.symbol, title: $draft.name, placeholder: "習慣名", focused: $nameFocused, titleIdentifier: "habit.name")
                            .id("habit.editor.top")
                    }
                    Section {
                        Stepper("1日の目標 \(draft.goalMinutes)分", value: $draft.goalMinutes, in: 1...1440, step: 5).accessibilityIdentifier("habit.goal")
                    }
                    Section("アイコン（\(HabitSymbols.all.count)種類）") {
                        SymbolPicker(selection: $draft.symbol) {
                            nameFocused = false
                            DispatchQueue.main.async {
                                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { proxy.scrollTo("habit.editor.top", anchor: .top) }
                            }
                        }.padding(.vertical, 8)
                    }
                    if !isNew { Section { Button("習慣と記録を削除", role: .destructive) { showDelete = true } } }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                .scrollDismissesKeyboard(.interactively)
                .dismissKeyboardOnBackgroundTap()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("editor.habit")
            }.navigationTitle(isNew ? "習慣を追加" : "習慣を編集").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { if store.saveHabit(draft) { dismiss() } else { error = store.errorMessage } }.bold().accessibilityIdentifier("editor.save") }
                }
                .confirmationDialog("この習慣とすべての記録を削除しますか？", isPresented: $showDelete, titleVisibility: .visible) {
                    Button("削除", role: .destructive) {
                        if store.deleteHabit(draft) {
                            if HabitTimer.shared.habitID == draft.id { HabitTimer.shared.reset() }
                            dismiss()
                        } else { error = store.errorMessage }
                    }
                    Button("キャンセル", role: .cancel) { showDelete = false }
                }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

struct ListEditor: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: PlannerList
    @State private var showDelete = false
    @State private var error: String?
    @FocusState private var nameFocused: Bool
    private let isNew: Bool
    init(list: PlannerList?) { _draft = State(initialValue: list ?? PlannerList(name: "")); isNew = list == nil }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        EditorTitleRow(symbol: draft.symbol, title: $draft.name, placeholder: "リスト名", focused: $nameFocused, titleIdentifier: "list.name")
                            .id("list.editor.top")
                    }
                    Section("アイコン") {
                        SymbolPicker(selection: $draft.symbol) {
                            nameFocused = false
                            DispatchQueue.main.async {
                                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { proxy.scrollTo("list.editor.top", anchor: .top) }
                            }
                        }
                    }
                    if !isNew && draft.id != PlannerList.inboxID { Section { Button("削除", role: .destructive) { showDelete = true }; Text("項目は受信箱に移動します。").font(.caption).foregroundStyle(.secondary) } }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                .scrollDismissesKeyboard(.interactively)
                .dismissKeyboardOnBackgroundTap()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("editor.list")
            }.navigationTitle(isNew ? "リストを追加" : "リストを編集").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { if store.saveList(draft) { dismiss() } else { error = store.errorMessage } }.bold().accessibilityIdentifier("editor.save") }
                }
                .confirmationDialog("このリストを削除しますか？", isPresented: $showDelete, titleVisibility: .visible) {
                    Button("削除", role: .destructive) { if store.deleteList(draft) { dismiss() } else { error = store.errorMessage } }
                        .accessibilityIdentifier("list.delete.confirm")
                    Button("キャンセル", role: .cancel) { showDelete = false }
                }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

struct LinkEditor: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SavedLink
    @State private var error: String?
    @State private var showDelete = false
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case title, url, notes }
    private let isNew: Bool
    init(link: SavedLink?) { _draft = State(initialValue: link ?? SavedLink(title: "", url: "")); isNew = link == nil || link?.url.isEmpty == true }
    var body: some View {
        NavigationStack {
            Form {
                TextField("タイトル", text: $draft.title).focused($focusedField, equals: .title).accessibilityIdentifier("link.title")
                TextField("URL", text: $draft.url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focusedField, equals: .url).accessibilityIdentifier("link.url")
                Picker("リスト", selection: $draft.listID) { ForEach(store.data.lists) { Text($0.name).tag($0.id) } }
                TextField("メモ", text: $draft.notes, axis: .vertical).lineLimit(3...10).focused($focusedField, equals: .notes).accessibilityIdentifier("link.notes")
                if !isNew { Button("削除", role: .destructive) { showDelete = true } }
                if let error { Text(error).foregroundStyle(.red) }
            }
                .scrollDismissesKeyboard(.interactively)
                .dismissKeyboardOnBackgroundTap()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("editor.link")
                .navigationTitle(isNew ? "リンクを追加" : "リンクを編集").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { if store.saveLink(draft) { dismiss() } else { error = store.errorMessage } }.bold().accessibilityIdentifier("editor.save") }
                }
                .confirmationDialog("このリンクを削除しますか？", isPresented: $showDelete, titleVisibility: .visible) {
                    Button("削除", role: .destructive) { if store.deleteLink(draft) { dismiss() } else { error = store.errorMessage } }
                    Button("キャンセル", role: .cancel) { showDelete = false }
                }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

private struct EditorTitleRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let symbol: String
    @Binding var title: String
    let placeholder: String
    var focused: FocusState<Bool>.Binding
    let titleIdentifier: String

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .frame(width: 76, height: 76)
                .foregroundStyle(Theme.accent)
                .background(Theme.accent.opacity(0.1), in: Circle())
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .accessibilityLabel(HabitSymbols.all.first { $0.symbol == symbol }?.name ?? "アイコン")
                .accessibilityIdentifier("editor.selectedSymbol")
            TextField(placeholder, text: $title)
                .font(.title3.weight(.semibold))
                .focused(focused)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .accessibilityIdentifier(titleIdentifier)
        }.padding(.vertical, 8)
    }
}
