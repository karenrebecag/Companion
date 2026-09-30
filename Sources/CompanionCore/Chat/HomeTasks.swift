import Foundation

/// Home as Incredible draws it (spec 16j §8): every conversation is a task,
/// grouped by day, newest first, with how long ago it last moved.
package enum HomeTasks {
    package enum Day: Sendable, Hashable {
        case today, yesterday, earlier
    }

    package enum Ago: Sendable, Equatable {
        case justNow
        case minutes(Int)
        case hours(Int)
        case days(Int)
    }

    package struct Section: Sendable, Equatable {
        package let day: Day
        package let rows: [ConversationMeta]
    }

    package static func sections(_ metas: [ConversationMeta], now: Date, calendar: Calendar) -> [Section] {
        let sorted = metas.sorted { $0.updatedAt > $1.updatedAt }
        let order: [Day] = [.today, .yesterday, .earlier]
        return order.compactMap { day in
            let rows = sorted.filter { self.day(of: $0.updatedAt, now: now, calendar: calendar) == day }
            return rows.isEmpty ? nil : Section(day: day, rows: rows)
        }
    }

    package static func ago(_ date: Date, now: Date) -> Ago {
        // A clock that runs ahead of the store reads as "now", never negative.
        let seconds = max(now.timeIntervalSince(date), 0)
        switch seconds {
        case ..<60: return .justNow
        case ..<3_600: return .minutes(Int(seconds / 60))
        case ..<86_400: return .hours(Int(seconds / 3_600))
        default: return .days(Int(seconds / 86_400))
        }
    }

    private static func day(of date: Date, now: Date, calendar: Calendar) -> Day {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return .yesterday }
        return .earlier
    }
}
