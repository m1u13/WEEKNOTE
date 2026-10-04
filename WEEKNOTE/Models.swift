import Foundation

enum TaskKind: String, Codable, CaseIterable, Identifiable {
    case todo, event
    var id: String { rawValue }
    var title: String { self == .todo ? "タスク" : "予定" }
}

enum EventCompletion: String, CaseIterable {
    case pending, early, onTime, late, unknown
    var title: String {
        switch self {
        case .pending: return "未完了"
        case .early: return "開始前に完了"
        case .onTime: return "時間内に完了"
        case .late: return "終了後に完了"
        case .unknown: return "完了（時刻不明）"
        }
    }
}

struct PlannerTask: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var notes: String
    var listID: UUID
    var date: Date?
    var durationMinutes: Int
    var kind: TaskKind
    var isCompleted: Bool
    var completedAt: Date?
    var completionDateOnly: Bool
    var isPriority: Bool
    var repeatsDaily: Bool
    var seriesID: UUID?
    var location: String

    init(id: UUID = UUID(), title: String, notes: String = "", listID: UUID = PlannerList.inboxID,
         date: Date? = nil, durationMinutes: Int = 30, kind: TaskKind = .todo,
         isCompleted: Bool = false, completedAt: Date? = nil, completionDateOnly: Bool = false, isPriority: Bool = false,
         repeatsDaily: Bool = false, seriesID: UUID? = nil, location: String = "") {
        self.id = id
        self.title = title
        self.notes = notes
        self.listID = listID
        self.date = date
        self.durationMinutes = durationMinutes
        self.kind = kind
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.completionDateOnly = completionDateOnly
        self.isPriority = isPriority
        self.repeatsDaily = repeatsDaily
        self.seriesID = seriesID
        self.location = location
    }

    var endDate: Date? { date?.addingTimeInterval(Double(durationMinutes) * 60) }

    /// A scheduled event is completed only by a user action. Crossing the scheduled time never completes it.
    var completionStatus: EventCompletion {
        guard isCompleted, let completedAt else { return .pending }
        if completionDateOnly { return .unknown }
        guard kind == .event, let date, let endDate else { return .onTime }
        if completedAt < date { return .early }
        if completedAt > endDate { return .late }
        return .onTime
    }

    func isOverdue(at now: Date = Date()) -> Bool {
        guard !isCompleted, let date else { return false }
        if kind == .event { return now > (endDate ?? date) }
        return CalendarSupport.calendar.startOfDay(for: now) > CalendarSupport.calendar.startOfDay(for: date)
    }
}

struct PlannerList: Identifiable, Codable, Equatable {
    static let inboxID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let inbox = PlannerList(id: inboxID, name: "受信箱", symbol: "tray")
    var id: UUID
    var name: String
    var symbol: String
    init(id: UUID = UUID(), name: String, symbol: String = "folder") {
        self.id = id; self.name = name; self.symbol = symbol
    }
}

struct Habit: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var symbol: String
    var goalMinutes: Int
    init(id: UUID = UUID(), name: String, symbol: String = "book", goalMinutes: Int = 30) {
        self.id = id; self.name = name; self.symbol = symbol; self.goalMinutes = goalMinutes
    }
}

struct HabitLog: Identifiable, Codable, Equatable {
    var id: UUID
    var habitID: UUID
    var date: Date
    var minutes: Int
    init(id: UUID = UUID(), habitID: UUID, date: Date = Date(), minutes: Int) {
        self.id = id; self.habitID = habitID; self.date = date; self.minutes = minutes
    }
}

struct SavedLink: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var url: String
    var listID: UUID
    var notes: String
    init(id: UUID = UUID(), title: String, url: String, listID: UUID = PlannerList.inboxID, notes: String = "") {
        self.id = id; self.title = title; self.url = url; self.listID = listID; self.notes = notes
    }
}

struct PlannerData: Codable, Equatable {
    var schemaVersion: Int = 1
    var tasks: [PlannerTask]
    var lists: [PlannerList]
    var habits: [Habit]
    var logs: [HabitLog]
    var links: [SavedLink]
    var isSample: Bool = false

    init(tasks: [PlannerTask] = [], lists: [PlannerList] = [.inbox], habits: [Habit] = [],
         logs: [HabitLog] = [], links: [SavedLink] = [], isSample: Bool = false) {
        self.tasks = tasks; self.lists = lists; self.habits = habits
        self.logs = logs; self.links = links; self.isSample = isSample
    }

    static var empty: PlannerData { PlannerData() }

    static func sample(referenceDate: Date) -> PlannerData { sample(relativeTo: referenceDate) }

    static func sample(relativeTo now: Date = Date()) -> PlannerData {
        let work = PlannerList(name: "仕事", symbol: "briefcase")
        let home = PlannerList(name: "暮らし", symbol: "house")
        let learning = PlannerList(name: "学び", symbol: "graduationcap")
        let reading = Habit(name: "読書", symbol: "book", goalMinutes: 30)
        let walking = Habit(name: "散歩", symbol: "figure.walk", goalMinutes: 20)
        let study = Habit(name: "英語", symbol: "character.book.closed", goalMinutes: 15)
        let today = CalendarSupport.calendar.startOfDay(for: now)
        let eventStart = CalendarSupport.calendar.date(bySettingHour: 15, minute: 0, second: 0, of: today)!
        let tasks = [
            PlannerTask(title: "資料を確認する", listID: work.id, date: today, isPriority: true),
            PlannerTask(title: "日用品を買う", listID: home.id, date: today),
            PlannerTask(title: "英単語を復習する", listID: learning.id, date: today, repeatsDaily: true),
            PlannerTask(title: "打ち合わせ", notes: "進捗と次の予定を確認", listID: work.id,
                        date: eventStart, durationMinutes: 45, kind: .event, location: "会議室")
        ]
        let logs = (0..<14).flatMap { offset -> [HabitLog] in
            let date = CalendarSupport.addingDays(-offset, to: today)
            return [HabitLog(habitID: reading.id, date: date, minutes: offset % 3 == 0 ? 30 : 15),
                    HabitLog(habitID: walking.id, date: date, minutes: offset % 4 == 0 ? 10 : 20)]
        }
        return PlannerData(tasks: tasks, lists: [.inbox, work, home, learning],
                           habits: [reading, walking, study], logs: logs, isSample: true)
    }
}

struct ParsedQuickEntry: Equatable {
    var title: String
    var date: Date?
    var hasTime: Bool
}

struct DayProgress {
    var completed: Int
    var total: Int
    var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
}

enum PlannerError: LocalizedError, Equatable {
    case invalid(String)
    case unsupportedVersion(Int)
    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .unsupportedVersion(let version): return "このバックアップの形式（\(version)）には対応していません。"
        }
    }
}
