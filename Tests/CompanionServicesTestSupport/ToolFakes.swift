import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionTestKit
import Foundation
import Testing

package struct FakePlaces: PlacesSearching {
    package var found: [FoundPlace]

    package init(found: [FoundPlace]) { self.found = found }
    package func search(_ query: String, near: String?) async -> [FoundPlace] { found }
}

package final class FakeChannel: FocusedAppSensing, OpenDocumentsSensing, ClipboardSensing,
    @unchecked Sendable
{
    private let app: String?
    private let documents: [String]
    private let clip: ClipboardSummary?
    private let delay: Duration
    private let fails: Bool
    private let lock = NSLock()
    private var _calls = 0
    package var calls: Int { lock.lock(); defer { lock.unlock() }; return _calls }

    package init(
        app: String? = nil, documents: [String] = [], clipboard: ClipboardSummary? = nil,
        delay: Duration = .zero, fails: Bool = false
    ) {
        self.app = app
        self.documents = documents
        self.clip = clipboard
        self.delay = delay
        self.fails = fails
    }

    private func count() { lock.lock(); _calls += 1; lock.unlock() }

    private func touch() async {
        count()
        if delay > .zero { try? await Task.sleep(for: delay) }
    }

    package func focusedApp() async -> String? { await touch(); return app }
    package func openDocuments() async -> [String] {
        await touch()
        if fails { return [] }
        return documents
    }
    package func clipboard() async -> ClipboardSummary? { await touch(); return clip }
}
