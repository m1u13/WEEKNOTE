import Foundation
import Combine
import CryptoKit

@MainActor
final class PlannerStore: ObservableObject {
    @Published private(set) var data: PlannerData
    @Published var errorMessage: String?
    let fileURL: URL
    private let now: () -> Date
    private var unreadableFile = false
    private var minutesByDay: [UUID: [String: Int]] = [:]
    private var totalsTimeZone = ""

    init(data initialData: PlannerData? = nil, fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.now = now
        self.fileURL = fileURL ?? Self.defaultFileURL()
        data = initialData ?? .sample(relativeTo: now())
        if let initialData {
            do {
                try Self.validate(initialData, now: now())
                try write(initialData)
            } catch { errorMessage = error.localizedDescription }
        } else if FileManager.default.fileExists(atPath: self.fileURL.path) {
            load()
        } else {
            do { try write(data) }
            catch { errorMessage = "データを保存できませんでした。\(error.localizedDescription)" }
        }
        rebuildHabitTotals()
    }

    private static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("WEEKNOTE", isDirectory: true).appendingPathComponent("planner.json")
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // Milliseconds preserve real completion timestamps and avoid locale-dependent date parsing.
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    func load() {
        do {
            let bytes = try Data(contentsOf: fileURL)
            let loaded = try Self.decoder().decode(PlannerData.self, from: bytes)
            try Self.validate(loaded, now: now())
            data = loaded
            rebuildHabitTotals()
            unreadableFile = false
            errorMessage = nil
        } catch {
            // Keep the original file intact. An explicit import/reset can recover it to a separate copy.
            unreadableFile = true
            errorMessage = "保存データを読み込めませんでした。元のファイルは保持されています。\(error.localizedDescription)"
        }
    }

    private func write(_ value: PlannerData) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder().encode(value).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    @discardableResult
    private func commit(_ value: PlannerData, allowRecovery: Bool = false) -> Bool {
        do {
            try Self.validate(value, now: now())
            if unreadableFile {
                guard allowRecovery else { throw PlannerError.invalid("元のデータを保持するため保存を停止しています。設定からバックアップを読み込むか、データをリセットしてください。") }
                let copy = fileURL.deletingLastPathComponent().appendingPathComponent("planner-unreadable-\(UUID().uuidString).json")
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.copyItem(at: fileURL, to: copy)
                }
            }
            try write(value)
            data = value
            rebuildHabitTotals()
            unreadableFile = false
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func saveTask(_ task: PlannerTask) -> Bool {
        var value = data
        var task = task
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.notes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        task.location = task.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if task.repeatsDaily { task.seriesID = task.seriesID ?? task.id }
        if task.isCompleted { task.completedAt = task.completedAt ?? now() }
        else { task.completedAt = nil; task.completionDateOnly = false }
        let old = value.tasks.first { $0.id == task.id }
        Self.upsert(task, in: &value.tasks)
        if task.isCompleted && old?.isCompleted != true { appendNextOccurrence(after: task, in: &value) }
        return commit(value)
    }

    @discardableResult
    func toggleTask(_ task: PlannerTask, at timestamp: Date? = nil) -> Bool { toggleTask(task.id, at: timestamp) }

    @discardableResult
    func toggleTask(_ id: UUID, at timestamp: Date? = nil) -> Bool {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return false }
        var value = data
        value.tasks[index].isCompleted.toggle()
        value.tasks[index].completedAt = value.tasks[index].isCompleted ? timestamp ?? now() : nil
        value.tasks[index].completionDateOnly = false
        if value.tasks[index].repeatsDaily { value.tasks[index].seriesID = value.tasks[index].seriesID ?? id }
        let completed = value.tasks[index]
        if completed.isCompleted { appendNextOccurrence(after: completed, in: &value) }
        return commit(value)
    }

    private func appendNextOccurrence(after task: PlannerTask, in value: inout PlannerData) {
        guard task.repeatsDaily, let series = task.seriesID else { return }
        let scheduled = task.date ?? CalendarSupport.calendar.startOfDay(for: task.completedAt ?? now())
        let completed = task.completedAt ?? now()
        let laterDay = max(CalendarSupport.calendar.startOfDay(for: scheduled), CalendarSupport.calendar.startOfDay(for: completed))
        let nextDay = CalendarSupport.addingDays(1, to: laterDay)
        let time = CalendarSupport.calendar.dateComponents([.hour, .minute, .second], from: scheduled)
        let nextDate = CalendarSupport.calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                                                     second: time.second ?? 0, of: nextDay) ?? nextDay
        guard !value.tasks.contains(where: {
            $0.seriesID == series && $0.kind == task.kind && $0.date.map { CalendarSupport.isSameDay($0, nextDate) } == true
        }) else { return }
        var next = task
        next.id = UUID()
        next.date = nextDate
        next.isCompleted = false
        next.completedAt = nil
        next.completionDateOnly = false
        value.tasks.append(next)
    }

    @discardableResult
    func deleteTask(_ task: PlannerTask) -> Bool { deleteTask(task.id) }
    @discardableResult
    func deleteTask(_ id: UUID) -> Bool {
        var value = data
        value.tasks.removeAll { $0.id == id }
        return commit(value)
    }

    @discardableResult
    func saveHabit(_ habit: Habit) -> Bool {
        var value = data
        var habit = habit
        habit.name = habit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        Self.upsert(habit, in: &value.habits)
        return commit(value)
    }

    @discardableResult
    func deleteHabit(_ habit: Habit) -> Bool { deleteHabit(habit.id) }
    @discardableResult
    func deleteHabit(_ id: UUID) -> Bool {
        var value = data
        value.habits.removeAll { $0.id == id }
        value.logs.removeAll { $0.habitID == id }
        return commit(value)
    }

    @discardableResult
    func addHabitLog(habitID: UUID, date: Date = Date(), minutes: Int) -> Bool {
        var value = data
        value.logs.append(HabitLog(habitID: habitID, date: CalendarSupport.calendar.startOfDay(for: date), minutes: minutes))
        return commit(value)
    }

    @discardableResult
    func addHabitLog(_ log: HabitLog) -> Bool {
        var value = data
        var log = log
        log.date = CalendarSupport.calendar.startOfDay(for: log.date)
        Self.upsert(log, in: &value.logs)
        return commit(value)
    }

    @discardableResult
    func deleteHabitLog(_ log: HabitLog) -> Bool { deleteHabitLog(log.id) }
    @discardableResult
    func deleteHabitLog(_ id: UUID) -> Bool {
        var value = data
        value.logs.removeAll { $0.id == id }
        return commit(value)
    }

    @discardableResult
    func saveList(_ list: PlannerList) -> Bool {
        var value = data
        var list = list
        list.name = list.name.trimmingCharacters(in: .whitespacesAndNewlines)
        Self.upsert(list, in: &value.lists)
        return commit(value)
    }

    @discardableResult
    func deleteList(_ list: PlannerList) -> Bool { deleteList(list.id) }
    @discardableResult
    func deleteList(_ id: UUID) -> Bool {
        guard id != PlannerList.inboxID else {
            errorMessage = "受信箱は削除できません。"
            return false
        }
        var value = data
        value.lists.removeAll { $0.id == id }
        // Tasks and saved links move to Inbox so deleting a list never removes their contents.
        for index in value.tasks.indices where value.tasks[index].listID == id { value.tasks[index].listID = PlannerList.inboxID }
        for index in value.links.indices where value.links[index].listID == id { value.links[index].listID = PlannerList.inboxID }
        return commit(value)
    }

    @discardableResult
    func saveLink(_ link: SavedLink) -> Bool {
        var value = data
        var link = link
        link.title = link.title.trimmingCharacters(in: .whitespacesAndNewlines)
        link.url = link.url.trimmingCharacters(in: .whitespacesAndNewlines)
        Self.upsert(link, in: &value.links)
        return commit(value)
    }

    @discardableResult
    func deleteLink(_ link: SavedLink) -> Bool { deleteLink(link.id) }
    @discardableResult
    func deleteLink(_ id: UUID) -> Bool {
        var value = data
        value.links.removeAll { $0.id == id }
        return commit(value)
    }

    func exportJSON() throws -> Data { try Self.encoder().encode(data) }

    func importJSON(_ bytes: Data) throws {
        guard bytes.count <= 20 * 1_024 * 1_024 else { throw PlannerError.invalid("バックアップは20 MB以内のJSONファイルを選択してください。") }
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw PlannerError.invalid("バックアップの形式を読み取れませんでした。")
        }
        let imported: PlannerData
        if object["schemaVersion"] != nil || object["links"] != nil || object["isSample"] != nil {
            // A malformed native backup must fail as native; do not reinterpret it as a website backup.
            imported = try Self.decoder().decode(PlannerData.self, from: bytes)
        } else {
            guard object["bookmarks"] != nil else { throw PlannerError.invalid("WEEKNOTEのバックアップを選択してください。") }
            imported = try Self.migrateWebsiteBackup(bytes)
        }
        try Self.validate(imported, now: now())
        guard commit(imported, allowRecovery: true) else { throw PlannerError.invalid(errorMessage ?? "データを保存できませんでした。") }
    }

    @discardableResult
    func reset(includeSamples: Bool = false) -> Bool {
        commit(includeSamples ? .sample(relativeTo: now()) : .empty, allowRecovery: true)
    }

    func listName(for id: UUID) -> String { data.lists.first { $0.id == id }?.name ?? "受信箱" }
    func tasks(on date: Date, kind: TaskKind? = nil) -> [PlannerTask] {
        data.tasks.filter {
            (kind == nil || $0.kind == kind) && $0.date.map { CalendarSupport.isSameDay($0, date) } == true
        }.sorted {
            if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
            if $0.isPriority != $1.isPriority { return $0.isPriority }
            return ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture)
        }
    }

    func habitMinutes(_ habit: Habit, on date: Date) -> Int { habitMinutes(habit.id, on: date) }
    func habitMinutes(_ id: UUID, on date: Date) -> Int {
        if totalsTimeZone != CalendarSupport.calendar.timeZone.identifier { rebuildHabitTotals() }
        return minutesByDay[id]?[CalendarSupport.dayKey(date)] ?? 0
    }

    private func rebuildHabitTotals() {
        var totals: [UUID: [String: Int]] = [:]
        for log in data.logs { totals[log.habitID, default: [:]][CalendarSupport.dayKey(log.date), default: 0] += log.minutes }
        minutesByDay = totals
        totalsTimeZone = CalendarSupport.calendar.timeZone.identifier
    }

    func dailyProgress(on date: Date) -> DayProgress {
        let scheduled = tasks(on: date)
        return DayProgress(completed: scheduled.filter(\.isCompleted).count, total: scheduled.count)
    }

    private static func upsert<T: Identifiable>(_ item: T, in items: inout [T]) where T.ID: Equatable {
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
        else { items.append(item) }
    }

    static func validate(_ value: PlannerData, now: Date = Date()) throws {
        guard value.schemaVersion == 1 else { throw PlannerError.unsupportedVersion(value.schemaVersion) }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw PlannerError.invalid(message) }
        }
        func unique<T: Identifiable>(_ items: [T], _ label: String) throws where T.ID: Hashable {
            try require(Set(items.map(\.id)).count == items.count, "\(label)のIDが重複しています。")
        }
        func text(_ string: String, _ label: String, max: Int = 300) throws {
            try require(!string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && string.count <= max,
                        "\(label)は1〜\(max)文字で入力してください。")
        }
        func validDate(_ date: Date) -> Bool {
            let seconds = date.timeIntervalSince1970
            return seconds.isFinite && (-2_209_161_600...7_258_291_200).contains(seconds)
                && (1900...2199).contains(CalendarSupport.calendar.component(.year, from: date))
        }
        try require(value.tasks.count <= 50_000 && value.logs.count <= 100_000 && value.habits.count <= 500
                    && value.lists.count <= 500 && value.links.count <= 10_000, "バックアップの件数が上限を超えています。")
        try unique(value.tasks, "タスク"); try unique(value.lists, "リスト"); try unique(value.habits, "習慣")
        try unique(value.logs, "記録"); try unique(value.links, "リンク")
        let lists = Set(value.lists.map(\.id))
        let habits = Set(value.habits.map(\.id))
        try require(lists.contains(PlannerList.inboxID), "バックアップに受信箱がありません。")
        for list in value.lists { try text(list.name, "リスト名"); try text(list.symbol, "アイコン名", max: 100) }
        for task in value.tasks {
            try text(task.title, "タスク名")
            try require(task.notes.count <= 20_000 && task.location.count <= 500, "メモまたは場所が長すぎます。")
            try require(lists.contains(task.listID), "タスクに存在しないリストが指定されています。")
            try require((1...1440).contains(task.durationMinutes), "所要時間は1〜1440分で入力してください。")
            try require(task.kind != .event || task.date != nil, "予定には日時が必要です。")
            if let date = task.date { try require(validDate(date), "タスクの日付が範囲外です。") }
            try require(task.isCompleted == (task.completedAt != nil), "完了状態と完了日時が一致していません。")
            try require(!task.completionDateOnly || task.isCompleted, "未完了のタスクに完了日の情報があります。")
            if let date = task.completedAt {
                try require(validDate(date) && date <= now.addingTimeInterval(60), "完了日時が未来になっています。")
            }
        }
        for habit in value.habits {
            try text(habit.name, "習慣名"); try text(habit.symbol, "アイコン名", max: 100)
            try require((1...1440).contains(habit.goalMinutes), "習慣の目標は1〜1440分で入力してください。")
        }
        var totals: [String: Int] = [:]
        for log in value.logs {
            try require(habits.contains(log.habitID), "記録に存在しない習慣が指定されています。")
            try require((1...1440).contains(log.minutes), "記録時間は1〜1440分で入力してください。")
            try require(validDate(log.date) && CalendarSupport.calendar.startOfDay(for: log.date) <= CalendarSupport.calendar.startOfDay(for: now), "未来の日付には習慣を記録できません。")
            let key = log.habitID.uuidString + CalendarSupport.dayKey(log.date)
            totals[key, default: 0] += log.minutes
            try require(totals[key, default: 0] <= 1440, "1つの習慣の記録は1日1440分までです。")
        }
        for link in value.links {
            try text(link.title, "リンク名"); try require(link.notes.count <= 20_000, "リンクのメモが長すぎます。")
            try require(lists.contains(link.listID), "リンクに存在しないリストが指定されています。")
            guard let url = URL(string: link.url), let host = url.host, !host.isEmpty,
                  let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme) else {
                throw PlannerError.invalid("リンクにはhttpまたはhttpsのURLを入力してください。")
            }
        }
    }
}

private extension PlannerStore {
    struct WebsiteBackup: Decodable {
        let tasks: [WebsiteTask]
        let lists: [WebsiteList]
        let habits: [WebsiteHabit]
        let logs: [WebsiteLog]
        let bookmarks: [WebsiteLink]
    }
    struct WebsiteTask: Decodable {
        let id: String
        let title: String
        let notes: String
        let listId: String
        let date: String
        let time: String
        let kind: TaskKind
        let done: Bool
        let completedAt: String
        let priority: Bool
        let repeats: Bool
        let location: String
        enum CodingKeys: String, CodingKey {
            case id, title, notes, listId, date, time, kind, done, completedAt, priority, location
            case repeats = "repeat"
        }
    }
    struct WebsiteList: Decodable { let id: String; let name: String; let icon: String }
    struct WebsiteHabit: Decodable { let id: String; let name: String; let icon: String; let goal: Int; let unit: String }
    struct WebsiteLog: Decodable { let id: String; let habitId: String; let date: String; let amount: Int }
    struct WebsiteLink: Decodable { let id: String; let title: String; let url: String; let listId: String; let notes: String }

    static func websiteUUID(_ sourceID: String, namespace: String) -> UUID {
        if let existing = UUID(uuidString: sourceID) { return existing }
        var bytes = Array(SHA256.hash(data: Data("WEEKNOTE:website:\(namespace):\(sourceID)".utf8)).prefix(16))
        // A namespaced custom UUID remains stable across repeated imports of non-UUID website identifiers.
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func websiteSymbol(_ original: String) -> String {
        ["book": "book", "run": "figure.run", "piano": "pianokeys", "leaf": "leaf",
         "folder": "folder", "layers": "square.3.layers.3d", "sun": "sun.max"][original] ?? "folder"
    }

    static func migrateWebsiteBackup(_ bytes: Data) throws -> PlannerData {
        let source = try JSONDecoder().decode(WebsiteBackup.self, from: bytes)
        func checkIDs(_ ids: [String], label: String) throws {
            guard ids.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), Set(ids).count == ids.count else {
                throw PlannerError.invalid("サイト版バックアップの\(label)のIDが空欄または重複しています。")
            }
        }
        try checkIDs(source.tasks.map(\.id), label: "タスク")
        try checkIDs(source.lists.map(\.id), label: "リスト")
        try checkIDs(source.habits.map(\.id), label: "習慣")
        try checkIDs(source.logs.map(\.id), label: "記録")
        try checkIDs(source.bookmarks.map(\.id), label: "リンク")
        let sourceLists = Set(source.lists.map(\.id))
        let sourceHabits = Set(source.habits.map(\.id))
        func listID(_ original: String) throws -> UUID {
            guard sourceLists.contains(original) else { throw PlannerError.invalid("サイト版バックアップに存在しないリスト「\(original)」が参照されています。") }
            return websiteUUID(original, namespace: "list")
        }
        func day(_ original: String, label: String) throws -> Date {
            guard let value = CalendarSupport.date(fromDayKey: original) else { throw PlannerError.invalid("\(label)の日付「\(original)」を読み取れません。") }
            return value
        }
        func completionDate(_ original: String, label: String) throws -> (Date, Bool) {
            if let value = CalendarSupport.date(fromDayKey: original) { return (value, true) }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let value = formatter.date(from: original) { return (value, false) }
            formatter.formatOptions = [.withInternetDateTime]
            if let value = formatter.date(from: original) { return (value, false) }
            throw PlannerError.invalid("完了済みタスク「\(label)」の完了日を読み取れません。")
        }
        var lists = source.lists.map { PlannerList(id: websiteUUID($0.id, namespace: "list"), name: $0.name, symbol: websiteSymbol($0.icon)) }
        if !lists.contains(where: { $0.id == PlannerList.inboxID }) { lists.insert(.inbox, at: 0) }
        let habits = try source.habits.map { habit -> Habit in
            let unit = habit.unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard ["分", "min", "minute", "minutes"].contains(unit) else {
                throw PlannerError.invalid("習慣「\(habit.name)」の単位「\(habit.unit)」は変換できません。iOS版の習慣は分単位で記録します。")
            }
            return Habit(id: websiteUUID(habit.id, namespace: "habit"), name: habit.name, symbol: websiteSymbol(habit.icon), goalMinutes: habit.goal)
        }
        let tasks = try source.tasks.map { original -> PlannerTask in
            var date: Date?
            if !original.date.isEmpty { date = try day(original.date, label: original.title) }
            if !original.time.isEmpty {
                guard let base = date, original.time.range(of: "^([01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil else {
                    throw PlannerError.invalid("タスク「\(original.title)」の時刻「\(original.time)」を読み取れません。")
                }
                let parts = original.time.split(separator: ":").compactMap { Int($0) }
                guard let timed = CalendarSupport.calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: base) else {
                    throw PlannerError.invalid("タスク「\(original.title)」の日時を読み取れません。")
                }
                date = timed
            }
            if original.kind == .event && original.time.isEmpty {
                throw PlannerError.invalid("予定「\(original.title)」に開始時刻がありません。")
            }
            var completedAt: Date?
            var dateOnly = false
            if original.done {
                let completion = try completionDate(original.completedAt, label: original.title)
                completedAt = completion.0; dateOnly = completion.1
            } else if !original.completedAt.isEmpty {
                throw PlannerError.invalid("未完了のタスク「\(original.title)」に完了日が設定されています。")
            }
            let id = websiteUUID(original.id, namespace: "task")
            let series = original.repeats ? websiteUUID("\(original.listId)\u{1f}\(original.title)", namespace: "series") : nil
            return PlannerTask(id: id, title: original.title, notes: original.notes, listID: try listID(original.listId), date: date,
                               kind: original.kind, isCompleted: original.done, completedAt: completedAt, completionDateOnly: dateOnly,
                               isPriority: original.priority, repeatsDaily: original.repeats, seriesID: series, location: original.location)
        }
        let logs = try source.logs.map { log -> HabitLog in
            guard sourceHabits.contains(log.habitId) else { throw PlannerError.invalid("サイト版バックアップに存在しない習慣「\(log.habitId)」が参照されています。") }
            return HabitLog(id: websiteUUID(log.id, namespace: "log"), habitID: websiteUUID(log.habitId, namespace: "habit"),
                            date: try day(log.date, label: "習慣の記録"), minutes: log.amount)
        }
        let links = try source.bookmarks.map {
            SavedLink(id: websiteUUID($0.id, namespace: "link"), title: $0.title, url: $0.url, listID: try listID($0.listId), notes: $0.notes)
        }
        return PlannerData(tasks: tasks, lists: lists, habits: habits, logs: logs, links: links)
    }
}
