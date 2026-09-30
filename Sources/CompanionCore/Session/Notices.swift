import Foundation

package enum NoticeLevel: Sendable, Equatable {
    case info, error
}

package struct Notice: Sendable, Equatable, Identifiable {
    package let id: UUID
    package let text: String
    package let level: NoticeLevel
    package let bornAt: TimeInterval

    package init(
        id: UUID = UUID(),
        text: String,
        level: NoticeLevel,
        bornAt: TimeInterval
    ) {
        self.id = id
        self.text = text
        self.level = level
        self.bornAt = bornAt
    }
}

package struct NoticeQueue: Sendable, Equatable {
    package static let lifetime: TimeInterval = 4
    package static let maxVisible = 3

    package private(set) var visible: [Notice] = []

    package init() {}

    package mutating func add(
        _ text: String, level: NoticeLevel, at now: TimeInterval
    ) {
        visible.append(Notice(text: text, level: level, bornAt: now))
        if visible.count > Self.maxVisible {
            visible.removeFirst(visible.count - Self.maxVisible)
        }
    }

    package mutating func expire(at now: TimeInterval) {
        visible.removeAll { now - $0.bornAt >= Self.lifetime }
    }
}
