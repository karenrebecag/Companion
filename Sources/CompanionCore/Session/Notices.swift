import Foundation

public enum NoticeLevel: Sendable, Equatable {
    case info, error
}

public struct Notice: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let text: String
    public let level: NoticeLevel
    public let bornAt: TimeInterval

    public init(
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

public struct NoticeQueue: Sendable, Equatable {
    public static let lifetime: TimeInterval = 4
    public static let maxVisible = 3

    public private(set) var visible: [Notice] = []

    public init() {}

    public mutating func add(
        _ text: String, level: NoticeLevel, at now: TimeInterval
    ) {
        visible.append(Notice(text: text, level: level, bornAt: now))
        if visible.count > Self.maxVisible {
            visible.removeFirst(visible.count - Self.maxVisible)
        }
    }

    public mutating func expire(at now: TimeInterval) {
        visible.removeAll { now - $0.bornAt >= Self.lifetime }
    }
}
