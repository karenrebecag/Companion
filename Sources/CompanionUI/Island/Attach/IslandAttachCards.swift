import CompanionCore
import SwiftUI

// Wave 16m-3: the staged attachments as Incredible's overlay draws them —
// 84 × 102 cards in a row that fades when it runs past the island, and the
// clip's captures in a 96 × 64 stack that opens into a strip. What goes
// where is `IslandAttachTrayModel`; these only paint it.

/// Everything staged, under the field.
struct IslandAttachTray: View {
    let staged: [AttachmentRef]
    let failed: [IslandAttachFailure]
    let onRemove: (AttachmentRef) -> Void
    let onDismissFailure: (IslandAttachFailure) -> Void
    /// Pictures already decoded, for renders that cannot wait for the loader.
    var pictures: [UUID: CGImage] = [:]
    /// For renders only: a test has no pointer or key focus to borrow.
    var pin: IslandAttachRevealPin? = nil
    var focusOnAppear = false

    @State private var expanded = false
    @State private var width: CGFloat = 0

    private var model: IslandAttachTrayModel {
        IslandAttachTrayModel.project(staged: staged, failed: failed, expanded: expanded)
    }

    var body: some View {
        let model = self.model
        VStack(alignment: .leading, spacing: Space.none) {
            if !model.strip.isEmpty {
                IslandCaptureStrip(captures: model.strip, pictures: pictures, onRemove: onRemove,
                                   onClose: { expanded = false })
            }
            if model.stack != nil || !model.cards.isEmpty {
                row(model)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        .onChange(of: model.stack?.count ?? model.strip.count) { _, count in
            if count <= 1 { expanded = false }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Localized.string("attach.list"))
    }

    /// A row that fits is laid out as is; only one that runs past the island
    /// scrolls, and fades at its end to say so.
    @ViewBuilder
    private func row(_ model: IslandAttachTrayModel) -> some View {
        if width > 0, model.overflows(available: width) {
            ScrollView(.horizontal, showsIndicators: false) { chips(model) }
                .mask(IslandRowFade())
        } else {
            chips(model)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chips(_ model: IslandAttachTrayModel) -> some View {
        HStack(alignment: .top, spacing: IslandAttachMetrics.rowGap) {
            if let stack = model.stack {
                IslandCaptureStack(model: stack, picture: pictures[stack.top.id],
                                   onOpen: { expanded = true }, onRemove: onRemove)
            }
            ForEach(model.cards) { item in
                IslandAttachCard(item: item, picture: picture(item), pin: pin, focusOnAppear: focusOnAppear, onRemove: { remove(item) })
            }
        }
        .padding(.top, IslandAttachMetrics.rowPaddingTop)
        .padding(.trailing, IslandAttachMetrics.rowPaddingTrailing)
    }

    private func picture(_ item: IslandAttachCardItem) -> CGImage? {
        guard case .staged(let ref) = item else { return nil }
        return pictures[ref.id]
    }

    private func remove(_ item: IslandAttachCardItem) {
        switch item {
        case .staged(let ref): onRemove(ref)
        case .failed(let failure): onDismissFailure(failure)
        }
    }
}

/// The end of a row with more past it.
private struct IslandRowFade: View {
    var body: some View {
        HStack(spacing: Space.none) {
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: IslandAttachMetrics.fadeLength)
        }
    }
}

/// A still of the remove disc. Nil follows the pointer and the key.
enum IslandAttachRevealPin: Equatable {
    case rest, hover, focus
}

enum IslandAttachReveal {
    /// The disc is up while the pointer is on the card or on the disc itself,
    /// or the key is on the control. The disc overhangs the card, so its own
    /// hover counts: in the reference it is a descendant and keeps :hover.
    /// local reference; Incredible .ci-att-card
    static func shown(cardHover: Bool, discHover: Bool, focused: Bool) -> Bool {
        cardHover || discHover || focused
    }

    /// Nil under Reduce Motion so the disc does not fade in.
    static func animation(reduceMotion: Bool) -> Animation? {
        ChromeMotion.animation(
            MotionCurve.animation(MotionCurve.ease, IslandAttachMetrics.revealSeconds), reduceMotion: reduceMotion)
    }
}

/// `ci-att-card`: a picture bleeds to the edge; any other file is a tile
/// with its type and name; a file the chat refused is washed in error.
struct IslandAttachCard: View {
    let item: IslandAttachCardItem
    var picture: CGImage?
    /// For renders only: a test has no pointer or key focus to borrow.
    var pin: IslandAttachRevealPin? = nil
    /// For renders only: puts the key on the remove control at mount.
    var focusOnAppear = false
    let onRemove: () -> Void

    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: IslandAttachMetrics.cardRadius)
    }

    var body: some View {
        ZStack {
            if case .staged(let ref) = item, ref.kind == .image {
                IslandAttachPicture(id: ref.id, path: ref.path, preloaded: picture)
                    .overlay(alignment: .topLeading) {
                        badge(overPicture: true).padding(IslandAttachMetrics.cardPadding)
                    }
            } else {
                tile
            }
        }
        .frame(width: IslandAttachMetrics.cardWidth, height: IslandAttachMetrics.cardHeight)
        .background(shape.fill(fill))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Neutral.white.color.opacity(IslandAttachMetrics.cardBorder),
                                    lineWidth: Stroke.hairline))
        .overlay(alignment: .topTrailing) {
            IslandRemoveOnHover(hovering: hovering, style: .card, pin: pin, focusOnAppear: focusOnAppear, name: item.name, action: onRemove)
                // Its centre on the corner, overhanging into the row's padding.
                .offset(x: IslandAttachMetrics.removeOffset, y: -IslandAttachMetrics.removeOffset)
        }
        .onHover { hovering = $0 }
        // The card must not swallow the remove control: the key and VoiceOver
        // reach that button on its own, so the card adds no action of its own.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: Space.none) {
            HStack(spacing: Space.x1) {
                badge(overPicture: false)
                if item.isError {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(Fonts.symbol(IslandAttachMetrics.nameSize, weight: .medium))
                        .foregroundStyle(IslandInk.destructive)
                }
            }
            Spacer(minLength: Space.none)
            Text(item.name)
                // The card is labelled with the name; reading it again inside
                // the contained children would make VoiceOver say it twice.
                .accessibilityHidden(true)
                // Geist at 12 already sets the measured 16 line: nothing added.
                .font(Fonts.geist(IslandAttachMetrics.nameSize).weight(.medium))
                .foregroundStyle(IslandInk.text)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(IslandAttachMetrics.cardPadding)
    }

    @ViewBuilder
    private func badge(overPicture: Bool) -> some View {
        if let ext = IslandAttachLabel.ext(item.name) {
            IslandExtBadge(text: ext, overPicture: overPicture)
                // Same reason as the name: the card's label already carries it.
                .accessibilityHidden(true)
        }
    }

    private var fill: Color {
        item.isError
            ? IslandAttachMetrics.errorTint.color.opacity(IslandAttachMetrics.errorAlpha)
            : Neutral.white.color.opacity(IslandAttachMetrics.cardTile)
    }

    private var label: String {
        item.isError ? String(format: Localized.string("island.attach.failed"), item.name) : item.name
    }
}

/// The type in capitals: 10 / 600, +0.04em, on white 13 %.
struct IslandExtBadge: View {
    let text: String
    /// Over a picture white 13 % disappears on a light photo; the badge
    /// borrows the remove disc's dark so it reads on any.
    var overPicture = false

    var body: some View {
        Text(verbatim: text)
            .font(Fonts.geist(IslandAttachMetrics.extSize).weight(.semibold))
            .tracking(IslandAttachMetrics.extSize * IslandAttachMetrics.extTracking)
            .foregroundStyle(IslandInk.text)
            .lineLimit(1)
            .padding(.vertical, IslandAttachMetrics.extPaddingY)
            .padding(.horizontal, IslandAttachMetrics.extPaddingX)
            .background(RoundedRectangle(cornerRadius: IslandAttachMetrics.extRadius).fill(fill))
    }

    private var fill: Color {
        overPicture
            ? IslandAttachMetrics.removeFill.color.opacity(IslandAttachMetrics.removeFillAlpha)
            : Neutral.white.color.opacity(IslandAttachMetrics.extFill)
    }
}

/// Where the remove disc sits and how it hides.
enum IslandRemoveStyle {
    /// `ci-att-card`: always in the key order and the accessibility tree, only
    /// its drawing fades. The card places it on its corner.
    case card
    /// The capture stack and strip are not cards: the disc is inset, shown only
    /// under the pointer, and VoiceOver removes through the tile's action.
    case capture

    /// The card's remove is a real control VoiceOver must reach; a capture
    /// removes through its tile's action instead.
    var hidesFromAccessibility: Bool { self == .capture }
}

struct IslandRemoveOnHover: View {
    let hovering: Bool
    var style: IslandRemoveStyle = .capture
    var pin: IslandAttachRevealPin? = nil
    var focusOnAppear = false
    let name: String
    let action: () -> Void

    @State private var keyFocused = false
    @State private var discHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: Bool {
        if let pin {
            return IslandAttachReveal.shown(cardHover: pin == .hover, discHover: false, focused: pin == .focus)
        }
        return IslandAttachReveal.shown(cardHover: hovering, discHover: discHovering, focused: keyFocused)
    }

    private var label: String { String(format: Localized.string("attach.remove"), name) }

    var body: some View {
        Group {
            switch style {
            case .card: card
            case .capture: capture
            }
        }
        .accessibilityHidden(style.hidesFromAccessibility)
    }

    private var card: some View {
        IconButton("xmark", label: label, size: .attachmentRemove, tone: .onMedia, pressable: true,
                   onFocus: { keyFocused = $0 }, revealed: shown, focusOnAppear: focusOnAppear, action: action)
            .onHover { discHovering = $0 }
            .animation(IslandAttachReveal.animation(reduceMotion: reduceMotion), value: shown)
    }

    private var capture: some View {
        CloseButton(variant: .onMedia, label: label, action: action)
            .padding(Space.x1)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .animation(ChromeMotion.animation(.expoOut(MotionTime.fast), reduceMotion: reduceMotion),
                       value: hovering)
    }
}

/// The clip's captures folded into one 96 × 64 tile, the newest on top and
/// the rest peeking under it; more than one carries its count and opens.
struct IslandCaptureStack: View {
    let model: IslandCaptureStackModel
    var picture: CGImage?
    let onOpen: () -> Void
    let onRemove: (AttachmentRef) -> Void

    @State private var hovering = false

    private var layers: Int { model.layers }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach((0 ..< layers).reversed(), id: \.self) { index in
                RoundedRectangle(cornerRadius: CaptureCardMetrics.radius)
                    .fill(IslandInk.popover)
                    .overlay(RoundedRectangle(cornerRadius: CaptureCardMetrics.radius)
                        .strokeBorder(IslandInk.hairline, lineWidth: Stroke.hairline))
                    .frame(width: IslandAttachMetrics.stackWidth, height: IslandAttachMetrics.stackHeight)
                    .offset(x: offset(index + 1), y: offset(index + 1))
            }
            IslandCaptureTile(ref: model.top, picture: picture)
                .overlay(alignment: .bottomLeading) {
                    if let badge = model.badge {
                        IslandCountBadge(text: badge).padding(Space.x1)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    IslandRemoveOnHover(hovering: hovering, name: model.top.name) { onRemove(model.top) }
                }
        }
        .padding(.trailing, offset(layers))
        .padding(.bottom, offset(layers))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if model.count > 1 { onOpen() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: Localized.string("island.attach.captures"), model.count))
        .accessibilityAddTraits(model.count > 1 ? .isButton : [])
        .accessibilityAction(named: Localized.string("island.attach.openCaptures")) {
            if model.count > 1 { onOpen() }
        }
        .accessibilityAction(named: String(format: Localized.string("attach.remove"), model.top.name)) {
            onRemove(model.top)
        }
    }

    private func offset(_ step: Int) -> CGFloat {
        CGFloat(step) * IslandAttachMetrics.stackOffset
    }
}

/// The opened stack: every capture on its own, gap 6, padding 10 / 10 / 0.
struct IslandCaptureStrip: View {
    let captures: [AttachmentRef]
    var pictures: [UUID: CGImage] = [:]
    let onRemove: (AttachmentRef) -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: IslandAttachMetrics.stripGap) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: IslandAttachMetrics.stripGap) {
                    ForEach(captures, id: \.id) { ref in
                        IslandStripCapture(ref: ref, picture: pictures[ref.id], onRemove: { onRemove(ref) })
                    }
                }
            }
            CloseButton(variant: .island, action: onClose)
        }
        .padding(.top, IslandAttachMetrics.stripPaddingTop)
        .padding(.horizontal, IslandAttachMetrics.stripPaddingX)
    }
}

private struct IslandStripCapture: View {
    let ref: AttachmentRef
    let picture: CGImage?
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        IslandCaptureTile(ref: ref, picture: picture)
            .overlay(alignment: .topTrailing) {
                IslandRemoveOnHover(hovering: hovering, name: ref.name, action: onRemove)
            }
            .onHover { hovering = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ref.name)
            .accessibilityAction(named: String(format: Localized.string("attach.remove"), ref.name), onRemove)
    }
}

/// One capture at the island's measured 96 × 64, the picture to the edge.
private struct IslandCaptureTile: View {
    let ref: AttachmentRef
    let picture: CGImage?

    var body: some View {
        CaptureCard(kind: .screenshot) {
            IslandAttachPicture(id: ref.id, path: ref.path, preloaded: picture)
                .frame(width: IslandAttachMetrics.stackWidth, height: IslandAttachMetrics.stackHeight)
        }
    }
}

/// The capture count: 18 high, radius 6, 10 / 600.
struct IslandCountBadge: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(Fonts.geist(IslandAttachMetrics.badgeSize).weight(.semibold))
            .foregroundStyle(IslandInk.text)
            .padding(.horizontal, IslandAttachMetrics.extPaddingX)
            .frame(minWidth: IslandAttachMetrics.badgeHeight, minHeight: IslandAttachMetrics.badgeHeight,
                   maxHeight: IslandAttachMetrics.badgeHeight)
            .background(RoundedRectangle(cornerRadius: IslandAttachMetrics.badgeRadius)
                .fill(IslandAttachMetrics.removeFill.color.opacity(IslandAttachMetrics.removeFillAlpha)))
    }
}

/// A stored attachment's picture, decoded once per attachment off the main
/// thread from the local copy; the tile shows through while it loads and
/// the file's kind icon stands in if it cannot be read.
struct IslandAttachPicture: View {
    let id: UUID
    let path: String
    @State private var image: CGImage?
    @State private var loaded: Bool

    init(id: UUID, path: String, preloaded: CGImage? = nil) {
        self.id = id
        self.path = path
        _image = State(initialValue: preloaded)
        _loaded = State(initialValue: preloaded != nil)
    }

    /// The clear base takes the tile's size; the picture fills it and is cut
    /// there, so a wide photo never widens its card.
    var body: some View {
        Color.clear
            .overlay {
                switch IslandPictureState.of(image: image, loaded: loaded) {
                case .picture:
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                case .fallback:
                    Image(systemName: "photo")
                        .font(Fonts.symbol(IslandAttachMetrics.fallbackIcon, weight: .regular))
                        .foregroundStyle(IslandInk.secondary)
                case .loading:
                    EmptyView()
                }
            }
            .clipped()
            .task(id: id) {
                guard !loaded else { return }
                let id = self.id, path = self.path
                image = await Task.detached(priority: .utility) {
                    IslandThumbnailCache.shared.image(id: id, path: path)
                }.value
                loaded = true
            }
    }
}
