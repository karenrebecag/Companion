import CompanionCore
import Foundation
import Observation
import SwiftUI

/// One diagram's draw, from "asked" to a picture or a reason it is text
/// (16m-5b). Every failure is a state the view shows; none is silent.
@MainActor
@Observable
final class IslandDiagramModel {
    enum State: Equatable {
        case loading
        case image(DiagramImage)
        case failed(DiagramFailure)
    }

    private(set) var state = State.loading
    /// Copy and download share it: with the popup's background, or without.
    private(set) var includesBackground = true

    func toggleBackground() { includesBackground.toggle() }

    /// Set when a download failed to write; cancelling the panel is not a failure.
    private(set) var saveFailed = false

    func record(_ result: DiagramSaveResult) {
        switch result {
        case .failed: saveFailed = true
        case .saved: saveFailed = false
        case .cancelled: break
        }
    }
    /// The text already drawn: SwiftUI may run the view's task again, and a
    /// finished picture must not flash back to "loading" for it.
    private var drawn: DiagramBlock?

    func load(_ block: DiagramBlock, renderer: (any DiagramRendering)?, width: Double) async {
        guard drawn != block else { return }
        guard let renderer else {
            state = .failed(.unavailable)
            return
        }
        state = .loading
        let outcome = await renderer.render(block, width: width)
        // The popup closed while it drew: nobody is looking.
        guard !Task.isCancelled else { return }
        switch outcome {
        case .image(let image):
            state = .image(image)
            drawn = block
        case .failed(let failure): state = .failed(failure)
        }
    }
}

/// The composition root's save panel: the PNG's bytes and a suggested name;
/// false when she cancels it. The island is a non-activating panel, so the
/// system's own panel cannot be opened from here (same reason as the file picker).
public typealias IslandFileSaver = @MainActor (Data, String) async -> DiagramSaveResult

extension EnvironmentValues {
    @Entry var fileSaver: IslandFileSaver?

    /// The popup's only way to a picture of a diagram; absent, the text shows
    /// as code. Set by the composition root, which owns the web view.
    @Entry var diagramRenderer: (any DiagramRendering)?
}
