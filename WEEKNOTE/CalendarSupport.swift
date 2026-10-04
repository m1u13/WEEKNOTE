import Foundation

enum CalendarSupport {
    /// Gregorian dates with ISO week numbering; days and event times follow the device time zone.
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .current
        value.locale = Locale(identifier: "ja_JP")
        value.firstWeekday = 2
        value.minimumDaysInFirstWeek = 4
        return value
    }

    static func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(fromDayKey key: String) -> Date? {
        guard key.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { return nil }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return validDate(year: parts[0], month: parts[1], day: parts[2])
    }

    static func startOfWeek(_ date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func weekDays(containing date: Date) -> [Date] {
        (0..<7).map { addingDays($0, to: startOfWeek(date)) }
    }

    static func monthDays(_ date: Date) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let range = calendar.range(of: .day, in: .month, for: date) else { return [] }
        return range.map { addingDays($0 - 1, to: interval.start) }
    }

    static func monthGridDays(_ date: Date) -> [Date] {
        guard let start = calendar.dateInterval(of: .month, for: date)?.start else { return [] }
        let startOfGrid = startOfWeek(start)
        return (0..<42).map { addingDays($0, to: startOfGrid) }
    }

    static func addingDays(_ count: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: count, to: date) ?? date
    }

    static func addingMonths(_ count: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: count, to: date) ?? date
    }

    static func monthTitle(_ date: Date) -> String {
        formatted(date, template: "yyyyMMMM")
    }

    static func formatted(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    static func weekNumber(_ date: Date) -> Int { calendar.component(.weekOfYear, from: date) }
    static func weekYear(_ date: Date) -> Int { calendar.component(.yearForWeekOfYear, from: date) }
    static func isSameDay(_ first: Date, _ second: Date) -> Bool { calendar.isDate(first, inSameDayAs: second) }

    private static func validDate(year: Int, month: Int, day: Int) -> Date? {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }

    /// Reads explicit relative dates, numeric dates, weekdays, and 24-hour times. Unrecognized text remains intact.
    static func parseQuickEntry(_ input: String, relativeTo reference: Date = Date()) -> ParsedQuickEntry {
        var title = String(input.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map { scalar -> Character in
            if (0xFF10...0xFF19).contains(scalar.value) { return Character(UnicodeScalar(scalar.value - 0xFEE0)!) }
            switch scalar.value {
            case 0xFF1A: return ":"
            case 0xFF0F: return "/"
            case 0xFF0D: return "-"
            case 0x3000: return " "
            default: return Character(scalar)
            }
        })
        var date: Date?
        var hasTime = false
        func firstMatch(_ pattern: String) -> (NSTextCheckingResult, [String])? {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = expression.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) else { return nil }
            let groups = (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: title).map { String(title[$0]) } ?? ""
            }
            return (match, groups)
        }
        func remove(_ match: NSTextCheckingResult) {
            if let range = Range(match.range, in: title) { title.replaceSubrange(range, with: " ") }
        }
        if let (match, groups) = firstMatch("(?<![A-Za-z])(明後日|明日|今日|tomorrow|today)(?=\\s|[0-9]|$)") {
            let word = groups[1].lowercased()
            let offset = word == "明後日" ? 2 : (word == "明日" || word == "tomorrow" ? 1 : 0)
            date = addingDays(offset, to: calendar.startOfDay(for: reference))
            remove(match)
        } else if let (match, groups) = firstMatch("(?<![0-9])(?:(20[0-9]{2})[-/年])?([0-9]{1,2})[-/月]([0-9]{1,2})日?(?![0-9])") {
            let year = Int(groups[1]) ?? calendar.component(.year, from: reference)
            if let month = Int(groups[2]), let day = Int(groups[3]), let value = validDate(year: year, month: month, day: day) {
                date = value
                remove(match)
            }
        } else if let (match, groups) = firstMatch("(来週)?([月火水木金土日])曜(?:日)?") {
            let weekdays = ["月", "火", "水", "木", "金", "土", "日"]
            if let index = weekdays.firstIndex(of: groups[2]) {
                let candidate = addingDays(index, to: startOfWeek(reference))
                date = groups[1] == "来週" || candidate < calendar.startOfDay(for: reference)
                    ? addingDays(7, to: candidate) : candidate
                remove(match)
            }
        }
        if let (match, groups) = firstMatch("(?<![0-9])([01]?[0-9]|2[0-3])[:：]([0-5][0-9])(?![0-9])(?:に|から)?"),
           let hour = Int(groups[1]), let minute = Int(groups[2]) {
            let base = date ?? calendar.startOfDay(for: reference)
            date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)
            hasTime = date != nil
            remove(match)
        } else if let (match, groups) = firstMatch("(?<![0-9])([01]?[0-9]|2[0-3])時(?:([0-5]?[0-9])分)?(?:に|から)?"),
                  let hour = Int(groups[1]) {
            let base = date ?? calendar.startOfDay(for: reference)
            date = calendar.date(bySettingHour: hour, minute: Int(groups[2]) ?? 0, second: 0, of: base)
            hasTime = date != nil
            remove(match)
        }
        title = title.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return ParsedQuickEntry(title: title, date: date, hasTime: hasTime)
    }
}

struct HolidayRecord: Codable, Equatable {
    let date: String
    let name: String
}

struct HolidayDataset: Codable {
    let sourceURL: String
    let verifiedOn: String
    let firstYear: Int
    let lastYear: Int
    let holidays: [HolidayRecord]
}

struct HolidayCalendar {
    static let shared = HolidayCalendar()
    let sourceURL: String
    let verifiedOn: String
    let coverageYears: ClosedRange<Int>?
    private let names: [String: String]

    init(bundle: Bundle = .main) {
        let url = bundle.url(forResource: "jp-holidays", withExtension: "json")
            ?? bundle.url(forResource: "jp-holidays", withExtension: "json", subdirectory: "Resources")
        if let url, let bytes = try? Data(contentsOf: url),
           let dataset = try? JSONDecoder().decode(HolidayDataset.self, from: bytes),
           dataset.firstYear <= dataset.lastYear {
            sourceURL = dataset.sourceURL
            verifiedOn = dataset.verifiedOn
            coverageYears = dataset.firstYear...dataset.lastYear
            names = Dictionary(dataset.holidays.map { ($0.date, $0.name) }, uniquingKeysWith: { first, _ in first })
        } else {
            sourceURL = "https://www8.cao.go.jp/chosei/shukujitsu/gaiyou.html"
            verifiedOn = ""
            coverageYears = nil
            names = [:]
        }
    }

    var coverageText: String {
        guard let coverageYears else { return "祝日データを読み込めませんでした。" }
        return "日本の祝日：\(coverageYears.lowerBound)〜\(coverageYears.upperBound)年（内閣府）"
    }

    func name(for date: Date) -> String? { names[CalendarSupport.dayKey(date)] }
    func isCovered(_ date: Date) -> Bool { coverageYears?.contains(CalendarSupport.calendar.component(.year, from: date)) ?? false }
}
