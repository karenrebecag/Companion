import Foundation

/// Keyboard and pointer events for the custom dropdown. Pure so tests do
/// not have to instantiate a SwiftUI Menu stand-in.
package struct DropdownSession: Equatable, Sendable {
    package var isOpen = false
    package var highlight = 0
    package private(set) var lastChosen: Int?
    package let count: Int

    package enum Event: Sendable, Equatable {
        case toggle, escape, clickOutside, choose, arrowUp, arrowDown
    }

    package init(count: Int) {
        self.count = count
    }

    package mutating func handle(_ event: Event) {
        switch event {
        case .toggle:
            guard count > 0 else { return }
            isOpen.toggle()
            if isOpen { lastChosen = nil }
        case .escape, .clickOutside:
            isOpen = false
        case .choose:
            guard isOpen, count > 0 else { return }
            lastChosen = highlight
            isOpen = false
        case .arrowDown:
            guard isOpen, count > 0 else { return }
            highlight = (highlight + 1) % count
        case .arrowUp:
            guard isOpen, count > 0 else { return }
            highlight = (highlight - 1 + count) % count
        }
    }
}
