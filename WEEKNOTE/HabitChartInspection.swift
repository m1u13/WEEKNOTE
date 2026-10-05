import Foundation
import CoreGraphics

enum HabitChartInspection {
    struct Position {
        let date: Date
        let x: CGFloat
    }

    /// A calendar bucket can span 23/25 hours or 28–31 days; its plotted center follows the actual interval.
    static func bucketCenter(_ date: Date, unit: Calendar.Component, calendar: Calendar) -> Date {
        guard let interval = calendar.dateInterval(of: unit, for: date) else { return date }
        return interval.start.addingTimeInterval(interval.duration / 2)
    }

    /// Resolve against every bucket, including buckets whose recorded value is zero.
    static func nearestDate(atX x: CGFloat, positions: [Position]) -> Date? {
        guard x.isFinite else { return nil }
        return positions.filter { $0.x.isFinite }.min { abs($0.x - x) < abs($1.x - x) }?.date
    }
}
