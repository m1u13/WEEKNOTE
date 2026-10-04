import SwiftUI
import UniformTypeIdentifiers

struct PlannerBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @EnvironmentObject private var store: PlannerStore
    @AppStorage("appearance") private var appearance = "system"
    @State private var document = PlannerBackupDocument()
    @State private var showExport = false
    @State private var showImport = false
    @State private var pendingImport: Data?
    @State private var confirmImport = false
    @State private var confirmReset = false
    @State private var confirmSample = false
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        List {
            Section("表示") {
                Picker("外観", selection: $appearance) { Text("端末設定").tag("system"); Text("ライト").tag("light"); Text("ダーク").tag("dark") }
                    .pickerStyle(.segmented).accessibilityIdentifier("appearance.picker")
            }
            Section("データ") {
                Button { do { document = PlannerBackupDocument(data: try store.exportJSON()); showExport = true } catch { self.error = error.localizedDescription } } label: { Label("バックアップを書き出す", systemImage: "square.and.arrow.up") }
                Button { showImport = true } label: { Label("バックアップを読み込む", systemImage: "square.and.arrow.down") }
                Text("JSONファイルで保存します。読み込むと現在の項目を置き換えます。WEEKNOTEサイト版のバックアップにも対応しています。").font(.caption).foregroundStyle(.secondary)
            }
            Section("祝日") {
                Text(HolidayCalendar.shared.coverageText).font(.subheadline)
                if let url = URL(string: HolidayCalendar.shared.sourceURL) { Link("内閣府の祝日データ", destination: url).font(.subheadline) }
            }
            Section {
                LabeledContent("タスク・予定", value: "\(store.data.tasks.count)件")
                LabeledContent("習慣", value: "\(store.data.habits.count)件")
                LabeledContent("習慣の記録", value: "\(store.data.logs.count)件")
                Button("サンプルデータに戻す") { confirmSample = true }
                Button("すべてのデータを削除", role: .destructive) { confirmReset = true }
            } footer: { Text("データはこの端末に保存されます。端末を移行する前にバックアップを書き出してください。").font(.caption) }
            if let message { Section { Text(message).font(.subheadline) } }
            if let error = error ?? store.errorMessage { Section { Text(error).font(.subheadline).foregroundStyle(.red) } }
            Section { LabeledContent("WEEKNOTE", value: "1.0") }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("設定")
            .fileExporter(isPresented: $showExport, document: document, contentType: .json, defaultFilename: "weeknote-\(CalendarSupport.dayKey(Date()))") { result in
                switch result { case .success: message = "バックアップを保存しました。"; error = nil; case .failure(let failure): error = failure.localizedDescription }
            }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 20 * 1024 * 1024 else { throw PlannerError.invalid("バックアップは20 MB以内のJSONファイルを選択してください。") }
                    pendingImport = try Data(contentsOf: url); confirmImport = true
                } catch { self.error = error.localizedDescription }
            }
            .confirmationDialog("現在のデータをバックアップの内容に置き換えますか？", isPresented: $confirmImport, titleVisibility: .visible) {
                Button("読み込む", role: .destructive) {
                    do { if let bytes = pendingImport { try store.importJSON(bytes); HabitTimer.shared.reset(); message = "バックアップを読み込みました。"; error = nil } } catch { self.error = error.localizedDescription }
                    pendingImport = nil
                }
                Button("キャンセル", role: .cancel) { pendingImport = nil }
            }
            .confirmationDialog("すべてのタスク、予定、習慣、記録を削除しますか？", isPresented: $confirmReset, titleVisibility: .visible) { Button("すべて削除", role: .destructive) { if store.reset() { HabitTimer.shared.reset(); message = "データを削除しました。"; error = nil } else { error = store.errorMessage } } }
            .confirmationDialog("現在のデータをサンプルデータに置き換えますか？", isPresented: $confirmSample, titleVisibility: .visible) { Button("置き換える", role: .destructive) { if store.reset(includeSamples: true) { HabitTimer.shared.reset(); message = "サンプルデータに戻しました。"; error = nil } else { error = store.errorMessage } } }
    }
}
