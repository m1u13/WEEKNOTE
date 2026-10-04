import SwiftUI

struct TaskEditor: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlannerTask
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var showDelete = false
    @State private var error: String?
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
                    TextField("タイトル", text: $draft.title, axis: .vertical).lineLimit(1...4).accessibilityIdentifier("task.title")
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
                        if draft.kind == .event { Stepper("所要時間 \(draft.durationMinutes)分", value: $draft.durationMinutes, in: 1...1440, step: 5); TextField("場所", text: $draft.location) }
                    }
                    Toggle("毎日繰り返す", isOn: $draft.repeatsDaily)
                }
                Section {
                    Picker("リスト", selection: $draft.listID) { ForEach(store.data.lists) { Text($0.name).tag($0.id) } }
                    Toggle("優先", isOn: $draft.isPriority)
                    TextField("メモ", text: $draft.notes, axis: .vertical).lineLimit(3...10)
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
            .navigationTitle(isNew ? (draft.kind == .event ? "予定を追加" : "タスクを追加") : "編集").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).bold().accessibilityIdentifier("editor.save") }
            }
            .confirmationDialog("この項目を削除しますか？", isPresented: $showDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) { if store.deleteTask(draft) { dismiss() } else { error = store.errorMessage } }
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
    @State private var draft: Habit
    @State private var error: String?
    @State private var showDelete = false
    private let isNew: Bool
    init(habit: Habit?) { _draft = State(initialValue: habit ?? Habit(name: "")); isNew = habit == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("習慣名", text: $draft.name).accessibilityIdentifier("habit.name")
                    Stepper("1日の目標 \(draft.goalMinutes)分", value: $draft.goalMinutes, in: 1...1440, step: 5)
                }
                Section("アイコン（\(HabitSymbols.all.count)種類）") { SymbolPicker(selection: $draft.symbol).padding(.vertical, 8) }
                if !isNew { Section { Button("習慣と記録を削除", role: .destructive) { showDelete = true } } }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(isNew ? "習慣を追加" : "習慣を編集").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { if store.saveHabit(draft) { dismiss() } else { error = store.errorMessage } }.bold().accessibilityIdentifier("editor.save") }
                }
                .confirmationDialog("この習慣とすべての記録を削除しますか？", isPresented: $showDelete, titleVisibility: .visible) {
                    Button("削除", role: .destructive) { if store.deleteHabit(draft) { dismiss() } else { error = store.errorMessage } }
                }.accessibilityIdentifier("editor.habit")
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

struct ListEditor: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlannerList
    @State private var showDelete = false
    @State private var error: String?
    private let isNew: Bool
    init(list: PlannerList?) { _draft = State(initialValue: list ?? PlannerList(name: "")); isNew = list == nil }
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("リスト名", text: $draft.name) }
                Section("アイコン") { SymbolPicker(selection: $draft.symbol) }
                if !isNew && draft.id != PlannerList.inboxID { Section { Button("削除", role: .destructive) { showDelete = true }; Text("項目は受信箱に移動します。").font(.caption).foregroundStyle(.secondary) } }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(isNew ? "リストを追加" : "リストを編集").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { if store.saveList(draft) { dismiss() } else { error = store.errorMessage } }.bold() }
                }
                .confirmationDialog("このリストを削除しますか？", isPresented: $showDelete, titleVisibility: .visible) { Button("削除", role: .destructive) { if store.deleteList(draft) { dismiss() } else { error = store.errorMessage } } }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

struct LinkEditor: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SavedLink
    @State private var error: String?
    @State private var showDelete = false
    private let isNew: Bool
    init(link: SavedLink?) { _draft = State(initialValue: link ?? SavedLink(title: "", url: "")); isNew = link == nil || link?.url.isEmpty == true }
    var body: some View {
        NavigationStack {
            Form {
                TextField("タイトル", text: $draft.title)
                TextField("URL", text: $draft.url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("リスト", selection: $draft.listID) { ForEach(store.data.lists) { Text($0.name).tag($0.id) } }
                TextField("メモ", text: $draft.notes, axis: .vertical).lineLimit(3...10)
                if !isNew { Button("削除", role: .destructive) { showDelete = true } }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(isNew ? "リンクを追加" : "リンクを編集").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { if store.saveLink(draft) { dismiss() } else { error = store.errorMessage } }.bold() }
                }
                .confirmationDialog("このリンクを削除しますか？", isPresented: $showDelete, titleVisibility: .visible) { Button("削除", role: .destructive) { if store.deleteLink(draft) { dismiss() } else { error = store.errorMessage } } }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}
