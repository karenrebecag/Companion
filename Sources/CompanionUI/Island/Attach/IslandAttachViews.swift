import AppKit
import CompanionCore
import SwiftUI

// Wave 16i-2 (spec 16i §2, §4): what the clip and a dropped file do from the
// island, and how a staged attachment looks there — a card under the field,
// not a trip to the window.

/// The three ways in and the drop, acting on the chat the window also uses:
/// a file staged here is the same pending attachment the window shows.
@MainActor
struct IslandAttachActions {
    let chat: ChatViewModel
    let voice: VoiceViewModel
    let grabber: (any RegionGrabbing)?
    /// Said once under the field ("nothing to read", a missing permission).
    let say: (String) -> Void

    func stage(_ url: URL) {
        guard let ref = chat.attach(url) else { return }
        // A live voice session hears about it now, as a window attach does.
        if voice.isActive { voice.push(ref) }
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
            urls.forEach(stage)
        case .airDrop:
            guard let service = NSSharingService(named: .sendViaAirDrop),
                  service.canPerform(withItems: urls) else {
                say(Localized.string("island.drop.airDropUnavailable"))
                return
            }
            service.perform(withItems: urls)
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

/// Staged attachments as Incredible's capture cards: a screenshot shows
/// itself, a file shows its icon and name; either can be taken back.
struct IslandStagedRow: View {
    let refs: [AttachmentRef]
    let onRemove: (AttachmentRef) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.x2) {
                ForEach(refs, id: \.id) { ref in card(ref) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Localized.string("attach.list"))
    }

    private func card(_ ref: AttachmentRef) -> some View {
        let kind: CaptureKind = ref.kind == .image ? .screenshot : .file
        return CaptureCard(kind: kind) {
            if kind == .screenshot {
                Image(nsImage: AttachmentLook.icon(for: ref))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: kind.width, height: CaptureCardMetrics.height)
            } else {
                VStack(alignment: .leading, spacing: Space.x1) {
                    Image(nsImage: AttachmentLook.icon(for: ref))
                        .resizable()
                        .frame(width: Space.x6, height: Space.x6)
                    Text(ref.name)
                        .font(GeistFont.uiCaption)
                        .foregroundStyle(IslandInk.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            CloseButton(variant: .onMedia,
                        label: String(format: Localized.string("attach.remove"), ref.name)) { onRemove(ref) }
                .padding(Space.x1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ref.name)
    }
}

/// The open notch under a dragged file (spec 16i §4, §11): two halves, the
/// one under the pointer lit with NotchNook's dashed blue.
struct IslandDropZones: View {
    let zone: IslandDropZone?

    var body: some View {
        HStack(spacing: Space.x2) {
            ForEach(IslandDropZone.allCases, id: \.self) { item in
                tile(item, lit: zone == item)
            }
        }
        .frame(height: IslandDropMetrics.height)
        .animation(.expoOut(MotionTime.fast), value: zone)
    }

    private func tile(_ item: IslandDropZone, lit: Bool) -> some View {
        VStack(spacing: Space.x2) {
            Image(systemName: item == .ask ? "text.bubble" : "dot.radiowaves.left.and.right")
                .font(Fonts.geist(TypeSize.sectionTitle))
            Text(Localized.string("island.drop." + item.rawValue))
                .font(GeistFont.uiCaption)
        }
        .foregroundStyle(lit ? IslandInk.text : IslandInk.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: IslandInk.cardRadius)
            .fill(lit ? IslandDropMetrics.litFill : IslandInk.popover))
        .overlay(RoundedRectangle(cornerRadius: IslandInk.cardRadius)
            .stroke(lit ? IslandDropMetrics.litStroke : IslandInk.hairline,
                    style: StrokeStyle(lineWidth: lit ? 1.5 : Stroke.hairline, dash: lit ? [6, 4] : [])))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}

enum IslandAttachMetrics {
    /// As long as a notice card's countdown (spec 16i §9).
    static let noteSeconds: Double = 6
}

enum IslandDropMetrics {
    static let height: CGFloat = 120
    /// NotchNook's lit zone, measured in the 18:11 recording.
    static let litFill = Color(red: 0.06, green: 0.16, blue: 0.34)
    static let litStroke = Color(red: 0.25, green: 0.55, blue: 1.0)
}
