import AppKit
import CompanionCore
import SwiftUI

// Wave 16i-2 (spec 16i §2, §4): what the clip and a dropped file do from the
// island. 16m-3 (D1): choosing a file happens here too — the picker feeds
// the chat's own staging and the window is never opened for it.

/// The clip's file picker. The composition root owns it because showing a
/// picker that takes the keyboard means activating the app, which the UI
/// never does (conformance `main-activation`). Empty is a cancel.
package typealias IslandFilePicker = @MainActor () async -> [URL]

/// The three ways in and the drop, acting on the chat the window also uses:
/// a file staged here is the same pending attachment the window shows.
@MainActor
struct IslandAttachActions {
    let chat: ChatViewModel
    let voice: VoiceViewModel
    let grabber: (any RegionGrabbing)?
    /// Said once under the field ("nothing to read", a missing permission).
    let say: (String) -> Void
    var pickFiles: IslandFilePicker?
    /// A file the chat refused: the island keeps it as a card in error.
    var onFail: (IslandAttachFailure) -> Void = { _ in }

    func stage(_ url: URL) {
        guard let ref = chat.attach(url) else {
            onFail(IslandAttachFailure(name: url.lastPathComponent))
            return
        }
        // A live voice session hears about it now, as a window attach does.
        if voice.isActive { voice.push(ref) }
    }

    /// Every file that reaches the island from outside — picked or dropped —
    /// passes the same filter the drop was hardened with (security review
    /// 16i-2): a folder's size is its inode and a link points elsewhere.
    /// What the filter keeps out is the user's choice all the same, so it
    /// shows as a card in error instead of vanishing (review 16m-3).
    func stageFiles(_ urls: [URL]) {
        let kept = Set(IslandDropTarget.regularFiles(urls))
        for url in urls {
            if kept.contains(url) {
                stage(url)
            } else {
                onFail(IslandAttachFailure(name: url.lastPathComponent))
            }
        }
    }

    func chooseFiles() async {
        guard let pickFiles else {
            say(Localized.string("island.attach.pickerUnavailable"))
            return
        }
        stageFiles(await pickFiles())
    }

    func screenshot() async {
        guard let url = await grab() else { return }
        stage(url)
        grabber?.discard(url)
    }

    /// The region's words, read on this Mac, for the field.
    func captureText() async -> String? {
        guard let url = await grab() else { return nil }
        defer { grabber?.discard(url) }
        guard let text = await grabber?.recognizeText(at: url) else {
            say(Localized.string("island.attach.noText"))
            return nil
        }
        return text
    }

    func drop(_ urls: [URL], zone: IslandDropZone) {
        switch zone {
        case .ask:
            stageFiles(urls)
        case .airDrop:
            let files = IslandDropTarget.regularFiles(urls)
            guard let service = NSSharingService(named: .sendViaAirDrop),
                  !files.isEmpty, service.canPerform(withItems: files) else {
                say(Localized.string("island.drop.airDropUnavailable"))
                return
            }
            service.perform(withItems: files)
        }
    }

    private func grab() async -> URL? {
        guard let grabber else {
            say(Localized.string("island.attach.captureFailed"))
            return nil
        }
        switch await grabber.capture() {
        case .captured(let url): return url
        case .cancelled: return nil
        case .failed: say(Localized.string("island.attach.captureFailed"))
        case .needsPermission: say(Localized.string("island.attach.needsScreen"))
        }
        return nil
    }
}

/// The open notch under a dragged file (spec 16i §4, §11): two dashed
/// zones at Incredible's 36-high drop shape (16m-3), the one under the
/// pointer lit with NotchNook's blue.
struct IslandDropZones: View {
    let zone: IslandDropZone?

    var body: some View {
        HStack(spacing: IslandAttachMetrics.rowGap) {
            ForEach(IslandDropZone.allCases, id: \.self) { item in
                tile(item, lit: zone == item)
            }
        }
        .animation(.expoOut(MotionTime.fast), value: zone)
    }

    private func tile(_ item: IslandDropZone, lit: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: IslandDropMetrics.radius)
        return HStack(spacing: Space.x1_5) {
            Image(systemName: item == .ask ? "text.bubble" : "dot.radiowaves.left.and.right")
                .font(Fonts.symbol(IslandDropMetrics.textSize, weight: .medium))
            Text(Localized.string("island.drop." + item.rawValue))
                .font(Fonts.geist(IslandDropMetrics.textSize).weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(lit ? IslandInk.text : IslandInk.secondary)
        .padding(.horizontal, IslandDropMetrics.paddingX)
        .frame(maxWidth: .infinity, minHeight: IslandDropMetrics.height, maxHeight: IslandDropMetrics.height)
        .background(shape.fill(lit ? IslandDropMetrics.litFill : Color.clear))
        .overlay(shape.strokeBorder(
            lit ? IslandDropMetrics.litStroke : Neutral.white.color.opacity(IslandDropMetrics.restStroke),
            style: StrokeStyle(lineWidth: IslandDropMetrics.dashWidth, dash: IslandDropMetrics.dash)))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}
