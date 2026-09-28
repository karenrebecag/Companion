import Foundation

/// The clip's dropdown (spec 16i §2): Incredible's three ways in, in its order.
public enum IslandAttachItem: String, Sendable, Equatable, CaseIterable {
    case chooseFile, captureText, screenshot
}

/// The system's own region picker (spec 16i §2): the crosshair, Space for a
/// window and Escape are the ones the user already knows.
public enum RegionCapture {
    public static let executable = "/usr/sbin/screencapture"

    public enum Outcome: Sendable, Equatable { case captured, cancelled, failed }

    /// `-i` region, `-x` no shutter sound, `-o` no window shadow in the image.
    public static func arguments(to path: String) -> [String] {
        ["-i", "-x", "-o", path]
    }

    /// PNG: lossless, so the text recognizer reads what was on screen.
    public static func fileName(id: UUID) -> String {
        "captura-\(id.uuidString.prefix(8).lowercased()).png"
    }

    /// Escape exits 0 and writes nothing: a change of mind, not an error.
    public static func outcome(exitCode: Int32, bytesWritten: Int?) -> Outcome {
        guard exitCode == 0 else { return .failed }
        guard let bytes = bytesWritten, bytes > 0 else { return .cancelled }
        return .captured
    }
}

/// One line the text recognizer found; `x`/`y` are its box's normalized
/// origin, bottom-left as Vision reports it.
public struct RecognizedLine: Sendable, Equatable {
    public let text: String
    public let x: Double
    public let y: Double

    public init(text: String, x: Double, y: Double) {
        self.text = text
        self.x = x
        self.y = y
    }
}

public enum RecognizedText {
    /// Boxes this close vertically share a row; Vision's baselines wobble.
    static let rowTolerance = 0.01

    /// Reading order: rows top to bottom, each row left to right.
    public static func join(_ lines: [RecognizedLine]) -> String? {
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

public enum IslandDraft {
    /// Captured text lands after what the user already typed, never glued to
    /// its last word, and never longer than any other inline text.
    public static func appending(_ text: String, to draft: String) -> String {
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
public enum IslandDropZone: String, Sendable, Equatable, CaseIterable {
    case ask, airDrop

    /// Dropped on the notch before the card opened: asking is the default.
    public static let fallback: IslandDropZone = .ask

    /// Screen or canvas coordinates alike: only the horizontal split matters.
    public static func at(_ point: CGPoint, in card: CGRect) -> IslandDropZone? {
        guard card.contains(point) else { return nil }
        return point.x < card.midX ? .ask : .airDrop
    }
}

/// What a drop may stage. A folder's reported size is its inode, so it would
/// pass the attachment ceiling and be copied whole; a symlink points outside
/// what the user dragged (security review 16i-2).
public enum IslandDropFilter {
    public static func keeps(isRegularFile: Bool, isSymbolicLink: Bool) -> Bool {
        isRegularFile && !isSymbolicLink
    }
}

/// Where the drag-only window sits. It takes plain clicks too, so at rest it
/// covers only the hardware notch, where nothing can be clicked; during a
/// drag it follows the card. Open, the island takes the drag itself.
public enum IslandDropCatch {
    public static func rect(shape: CGRect, hardwareNotch: Bool, resting: Bool, dropping: Bool) -> CGRect {
        if dropping { return shape }
        return resting && hardwareNotch ? shape : .zero
    }
}

public enum IslandComposing {
    /// The field stays open while there is something to send. With the main
    /// window in front the staged chips are drawn there, not twice.
    public static func active(
        focused: Bool, draft: String, confirmingClear: Bool, staged: Int, mainInFront: Bool
    ) -> Bool {
        focused || !draft.isEmpty || confirmingClear || (staged > 0 && !mainInFront)
    }
}

/// What one pass of the region picker produced.
public enum RegionGrab: Sendable, Equatable {
    case captured(URL)
    case cancelled
    case failed
    /// Without Screen Recording the picker returns the wallpaper, not the windows.
    case needsPermission
}

/// Port for the clip's captures: the picker, the local text recognizer and
/// the temporary file's end.
public protocol RegionGrabbing: Sendable {
    func capture() async -> RegionGrab
    func recognizeText(at url: URL) async -> String?
    func discard(_ url: URL)
}
