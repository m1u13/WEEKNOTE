import SwiftUI
import UIKit

struct HabitContextActions: ViewModifier {
    @EnvironmentObject private var store: PlannerStore
    var habit: Habit
    var open: () -> Void
    var edit: () -> Void
    @State private var confirmDelete = false
    @State private var showError = false

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(action: edit) { Label("編集", systemImage: "pencil") }
            Button(role: .destructive) { confirmDelete = true } label: { Label("削除", systemImage: "trash") }
        }
        .confirmationDialog("「\(habit.name)」とすべての記録を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if store.deleteHabit(habit) {
                    if HabitTimer.shared.habitID == habit.id { HabitTimer.shared.reset() }
                } else { showError = true }
            }
        }
        .alert("保存できませんでした", isPresented: $showError) { Button("閉じる", role: .cancel) {} } message: { Text(store.errorMessage ?? "操作をやり直してください。") }
    }
}

struct TaskContextActions: ViewModifier {
    @EnvironmentObject private var store: PlannerStore
    var task: PlannerTask
    var edit: () -> Void
    @State private var confirmDelete = false
    @State private var showError = false

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(action: edit) { Label("編集", systemImage: "pencil") }
            Button { if !store.toggleTask(task) { showError = true } } label: { Label(task.isCompleted ? "未完了に戻す" : "完了にする", systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark") }
            Button {
                var updated = task; updated.isPriority.toggle()
                if !store.saveTask(updated) { showError = true }
            } label: { Label(task.isPriority ? "優先を解除" : "優先にする", systemImage: task.isPriority ? "star.slash" : "star") }
            Menu {
                ForEach(store.data.lists) { list in
                    Button {
                        var updated = task; updated.listID = list.id
                        if !store.saveTask(updated) { showError = true }
                    } label: { Label(list.name, systemImage: list.id == task.listID ? "checkmark" : list.symbol) }
                }
            } label: { Label("リストに移動", systemImage: "folder") }
            Button { UIPasteboard.general.string = task.title } label: { Label("タイトルをコピー", systemImage: "doc.on.doc") }
            Button(role: .destructive) { confirmDelete = true } label: { Label("削除", systemImage: "trash") }
        }
        .confirmationDialog("「\(task.title)」を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) { if !store.deleteTask(task) { showError = true } }
        }
        .alert("保存できませんでした", isPresented: $showError) { Button("閉じる", role: .cancel) {} } message: { Text(store.errorMessage ?? "操作をやり直してください。") }
    }
}

struct ListContextActions: ViewModifier {
    @EnvironmentObject private var store: PlannerStore
    var list: PlannerList
    var edit: () -> Void
    var addTask: () -> Void
    @State private var confirmDelete = false
    @State private var showError = false

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(action: addTask) { Label("タスクを追加", systemImage: "plus") }
            Button(action: edit) { Label("編集", systemImage: "pencil") }
            if list.id != PlannerList.inboxID {
                Button(role: .destructive) { confirmDelete = true } label: { Label("削除", systemImage: "trash") }
            }
        }
        .confirmationDialog("「\(list.name)」を削除しますか？項目は受信箱に移動します。", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) { if !store.deleteList(list) { showError = true } }
        }
        .alert("保存できませんでした", isPresented: $showError) { Button("閉じる", role: .cancel) {} } message: { Text(store.errorMessage ?? "操作をやり直してください。") }
    }
}

struct LinkContextActions: ViewModifier {
    @EnvironmentObject private var store: PlannerStore
    var link: SavedLink
    var edit: () -> Void
    @State private var confirmDelete = false
    @State private var showError = false

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(action: edit) { Label("編集", systemImage: "pencil") }
            Button { UIPasteboard.general.string = link.url } label: { Label("URLをコピー", systemImage: "doc.on.doc") }
            if let url = URL(string: link.url) { ShareLink(item: url) { Label("共有", systemImage: "square.and.arrow.up") } }
            Button(role: .destructive) { confirmDelete = true } label: { Label("削除", systemImage: "trash") }
        }
        .confirmationDialog("「\(link.title)」を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) { if !store.deleteLink(link) { showError = true } }
        }
        .alert("保存できませんでした", isPresented: $showError) { Button("閉じる", role: .cancel) {} } message: { Text(store.errorMessage ?? "操作をやり直してください。") }
    }
}

struct PressFeedbackStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(InteractionMotion.animation(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
