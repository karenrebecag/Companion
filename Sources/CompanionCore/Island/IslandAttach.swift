import Foundation

/// The clip's dropdown (spec 16i §2): Incredible's three ways in, in its order.
package enum IslandAttachItem: String, Sendable, Equatable, CaseIterable {
    case chooseFile, captureText, screenshot
}

/// The system's own region picker (spec 16i §2): the crosshair, Space for a
/// window and Escape are the ones the user already knows.
package enum RegionCapture {
    package static let executable = "/usr/sbin/screencapture"

    package enum Outcome: Sendable, Equatable { case captured, cancelled, failed }

    /// `-i` region, `-x` no shutter sound, `-o` no window shadow in the image.
    package static func arguments(to path: String) -> [String] {
        ["-i", "-x", "-o", path]
    }

    /// PNG: lossless, so the text recognizer reads what was on screen.
    package static func fileName(id: UUID) -> String {
        "\(prefix)\(id.uuidString.prefix(8).lowercased()).png"
    }

    static let prefix = "captura-"
    static let suffix = ".png"
    static let idLength = 8

    /// A capture is told apart by the exact name `fileName` gives it —
    /// eight lowercase hex digits — so a user's own `captura-final.png`
    /// stays a file (review 16m-3). The stored copy keeps the name, and
    /// nothing else about a PNG says where it came from.
    package static func isCapture(name: String) -> Bool {
        guard name.hasPrefix(prefix), name.hasSuffix(suffix),
              name.count == prefix.count + idLength + suffix.count else { return false }
        let id = name.dropFirst(prefix.count).dropLast(suffix.count)
        return id.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// Escape exits 0 and writes nothing: a change of mind, not an error.
    package static func outcome(exitCode: Int32, bytesWritten: Int?) -> Outcome {
        guard exitCode == 0 else { return .failed }
        guard let bytes = bytesWritten, bytes > 0 else { return .cancelled }
        return .captured
    }
}

/// One line the text recognizer found; `x`/`y` are its box's normalized
/// origin, bottom-left as Vision reports it.
package struct RecognizedLine: Sendable, Equatable {
    package let text: String
    package let x: Double
    package let y: Double

    package init(text: String, x: Double, y: Double) {
        self.text = text
        self.x = x
        self.y = y
    }
}

package enum RecognizedText {
    /// Boxes this close vertically share a row; Vision's baselines wobble.
    static let rowTolerance = 0.01

    /// Reading order: rows top to bottom, each row left to right.
    package static func join(_ lines: [RecognizedLine]) -> String? {
        let kept = lines
            .map { RecognizedLine(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), x: $0.x, y: $0.y) }
            .filter { !$0.text.isEmpty }
            .sorted { $0.y > $1.y }
        var rows: [[RecognizedLine]] = []
        for line in kept {
            if let top = rows.last?.first, abs(top.y - line.y) <= rowTolerance {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        let text = rows
            .map { row in row.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
        return text.isEmpty ? nil : text
    }
}

package enum IslandDraft {
    /// Captured text lands after what the user already typed, never glued to
    /// its last word, and never longer than any other inline text.
    package static func appending(_ text: String, to draft: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return draft }
        let clipped = AttachmentPolicy.clipInline(clean)
        guard !draft.isEmpty else { return clipped }
        let separator = draft.last?.isWhitespace == true ? "" : " "
        return draft + separator + clipped
    }
}

/// Where a file dragged onto the open notch goes (spec 16i §4). The tray is
/// 16i-5; until then the card has two halves.
package enum IslandDropZone: String, Sendable, Equatable, CaseIterable {
    case ask, airDrop

    /// Dropped on the notch before the card opened: asking is the default.
    package static let fallback: IslandDropZone = .ask

    /// Screen or canvas coordinates alike: only the horizontal split matters.
    package static func at(_ point: CGPoint, in card: CGRect) -> IslandDropZone? {
        guard card.contains(point) else { return nil }
        return point.x < card.midX ? .ask : .airDrop
    }
}

/// What a drop may stage. A folder's reported size is its inode, so it would
/// pass the attachment ceiling and be copied whole; a symlink points outside
/// what the user dragged (security review 16i-2).
package enum IslandDropFilter {
    package static func keeps(isRegularFile: Bool, isSymbolicLink: Bool) -> Bool {
        isRegularFile && !isSymbolicLink
    }
}

/// Where the drag-only window sits. It takes plain clicks too, so at rest it
/// covers only the hardware notch, where nothing can be clicked; during a
/// drag it follows the card. Open, the island takes the drag itself.
package enum IslandDropCatch {
    package static func rect(shape: CGRect, hardwareNotch: Bool, resting: Bool, dropping: Bool) -> CGRect {
        if dropping { return shape }
        return resting && hardwareNotch ? shape : .zero
    }
}

package enum IslandComposing {
    /// The field stays open while there is something to send. With the main
    /// window in front the staged chips are drawn there, not twice. While the
    /// clip's picker is up the island must not fold away under it, even if
    /// activating the app brought the window forward (16m-3).
    package static func active(
        focused: Bool, draft: String, confirmingClear: Bool, staged: Int, mainInFront: Bool,
        picking: Bool = false, choiceFocused: Bool = false
    ) -> Bool {
        focused || choiceFocused || !draft.isEmpty || confirmingClear || picking || (staged > 0 && !mainInFront)
    }
}

/// What one pass of the region picker produced.
package enum RegionGrab: Sendable, Equatable {
    case captured(URL)
    case cancelled
    case failed
    /// Without Screen Recording the picker returns the wallpaper, not the windows.
    case needsPermission
}

/// Port for the clip's captures: the picker, the local text recognizer and
/// the temporary file's end.
package protocol RegionGrabbing: Sendable {
    func capture() async -> RegionGrab
    func recognizeText(at url: URL) async -> String?
    func discard(_ url: URL)
}

/// Where the keyboard goes when the clip's picker closes (review 16m-3).
package enum IslandPickerFocus {
    /// Back to the app that had it — unless that was Companion, the app is
    /// gone, or the user already moved to another app while the panel was up.
    package static func handsBack(previousIsCompanion: Bool, previousRunning: Bool, frontIsCompanion: Bool) -> Bool {
        !previousIsCompanion && previousRunning && frontIsCompanion
    }
}
