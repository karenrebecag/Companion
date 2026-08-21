import CompanionCore
import Observation

/// Settings needs the catalog without importing Services: the app layer feeds
/// it whatever it detected at launch.
@Observable
@MainActor
public final class ExecutorChoice {
    public private(set) var available: [ExecutorDescriptor]
    public var selected: ExecutorID {
        didSet { onSelect(selected) }
    }

    private let onSelect: (ExecutorID) -> Void

    public init(
        available: [ExecutorDescriptor],
        selected: ExecutorID,
        onSelect: @escaping (ExecutorID) -> Void
    ) {
        self.available = available
        self.selected = selected
        self.onSelect = onSelect
    }

    public func refresh(_ descriptors: [ExecutorDescriptor], selected: ExecutorID) {
        available = descriptors
        if self.selected != selected { self.selected = selected }
    }

    /// A single executor is not a choice: hide the picker instead of showing
    /// a menu with one entry.
    public var isMeaningful: Bool { available.count > 1 }
}
