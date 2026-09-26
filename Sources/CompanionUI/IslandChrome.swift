import AppKit
import CompanionCore
import QuartzCore
import SwiftUI

/// The island's geometry (Wave 12b; 16f moved it into the notch). The
/// window is one fixed canvas hanging from the top edge; what grows is the
/// black shape inside it, so nothing is ever animated with `setFrame`.
public enum IslandChrome {
    /// The meter circle in the status row and the field row.
    public static let meterSide: CGFloat = 32
    /// The first half of opening: wide and low (241 pt measured).
    public static let pillWidth: CGFloat = 240
    public static let barWidth: CGFloat = 320
    /// The open panel, measured at 492 pt in the recording.
    public static let nudgeWidth: CGFloat = 492
    public static let cardWidth: CGFloat = 492
    /// Room for the widest panel, its shoulders and its shadow.
    public static let canvasWidth: CGFloat = 560
    public static let canvasHeight: CGFloat = 620
    /// Below the shape's bottom edge the shadow needs somewhere to fall.
    static let shadowRoom: CGFloat = 28

    public static func width(for size: IslandState.Size, notch: Notch) -> CGFloat {
        switch size {
        case .hidden, .pebble: notch.width
        case .nudge: nudgeWidth
        case .bar: barWidth
        case .card: cardWidth
        }
    }

    /// The same rectangle for every size: the window never moves.
    public static func canvasFrame(for notch: Notch) -> CGRect {
        CGRect(x: (notch.midX - canvasWidth / 2).rounded(), y: notch.top - canvasHeight,
               width: canvasWidth, height: canvasHeight)
    }

    /// At rest the shape is the notch; open, the role's width and the
    /// content's height, never shorter than the notch nor taller than the canvas.
    public static func shapeSize(for size: IslandState.Size, contentHeight: CGFloat, notch: Notch) -> CGSize {
        if IslandMotion.rests(size) { return CGSize(width: notch.width, height: notch.height) }
        let height = min(max(contentHeight, notch.height), canvasHeight - shadowRoom)
        return CGSize(width: width(for: size, notch: notch), height: height)
    }

    /// The shape in screen coordinates (origin bottom-left), for the pointer.
    public static func shapeRect(_ size: CGSize, notch: Notch) -> CGRect {
        CGRect(x: notch.midX - size.width / 2, y: notch.top - size.height,
               width: size.width, height: size.height)
    }

    /// Closed on every edge: the pointer pinned to the top of the screen is
    /// on the notch, and `CGRect.contains` would say it is not.
    public static func pointerInside(_ point: CGPoint, rect: CGRect) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    /// An open dropdown hangs past the shape (16o-1) and still takes clicks.
    public static func pointerInside(_ point: CGPoint, shape: CGRect, portal: CGRect?) -> Bool {
        pointerInside(point, rect: shape) || portal.map { pointerInside(point, rect: $0) } ?? false
    }

    /// The portal reports in the canvas (origin top-left); the pointer is in
    /// screen coordinates (origin bottom-left).
    public static func portalScreenRect(_ rect: CGRect, canvas: CGRect) -> CGRect {
        CGRect(x: canvas.minX + rect.minX, y: canvas.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The click area follows the shape, not its destination: growing, it
    /// takes the new size at once; shrinking, it keeps the old one until the
    /// spring has brought the shape down (code review 16f).
    public static func hitSizes(current: CGSize, target: CGSize) -> (now: CGSize, later: CGSize?) {
        let shrinks = target.width * target.height < current.width * current.height
        return shrinks ? (current, target) : (target, nil)
    }

    /// The close spring settles (~180 ms), with margin.
    public static let hitShrinkDelay: Double = 0.3

    /// NotchNook's peek, measured (spec 16i §11): 294×38 settles at ~308×45.
    static let peekGrowth = CGSize(width: 20, height: 9)

    static func peekSize(notch: Notch) -> CGSize {
        CGSize(width: notch.width + peekGrowth.width, height: notch.height + peekGrowth.height)
    }

    /// Peeking, the pointer must not fall off the edge the shape just grew.
    /// The peek is only drawn at rest, so only at rest does it widen the
    /// area (security review 16i-1).
    static func hitSize(base: CGSize, peeking: Bool, resting: Bool, notch: Notch) -> CGSize {
        guard peeking, resting else { return base }
        let peek = peekSize(notch: notch)
        return CGSize(width: max(base.width, peek.width), height: max(base.height, peek.height))
    }

    /// At rest the shape is hardware and casts nothing; the peek already
    /// lifts off the screen, like the open panel.
    static func shadowOpacity(resting: Bool, peeking: Bool) -> Double {
        resting && !peeking ? 0 : 1
    }

    /// Only the shape takes clicks. Keyboard focus does not widen it: typing
    /// needs no mouse, and a click outside must reach the app behind, which
    /// is also what takes the keyboard back (security review 16f).
    public static func ignoresPointer(inside: Bool, isKey: Bool) -> Bool {
        !inside
    }

    /// `from` is the shape as drawn: phase 1 never pulls a peeking shape
    /// back before phase 2 grows it (M1, nothing jumps).
    static func size(of stage: IslandMotion.Stage, target: CGSize, notch: Notch, from: CGSize = .zero) -> CGSize {
        switch stage {
        case .notch: CGSize(width: notch.width, height: notch.height)
        case .pill: CGSize(width: max(pillWidth, from.width), height: max(notch.height, from.height))
        case .full: target
        }
    }
}

/// The notch the island lives under, shared by the window and the view so
/// a display change moves both at once.
@Observable
@MainActor
public final class IslandGeometry {
    public var notch: Notch
    /// The pointer is on the resting notch and it leans out (spec 16i §11).
    public var peeking = false
    /// The open dropdown's frame in the canvas, for the click area (16o-1).
    public var portal: CGRect?

    public init(notch: Notch = NotchGeometry.notch(on: ScreenShape(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleMaxY: 945, safeTop: 0,
        leftAuxWidth: nil, rightAuxWidth: nil))) {
        self.notch = notch
    }
}

extension NSScreen {
    var islandShape: ScreenShape {
        ScreenShape(
            frame: frame, visibleMaxY: visibleFrame.maxY, safeTop: safeAreaInsets.top,
            leftAuxWidth: auxiliaryTopLeftArea?.width, rightAuxWidth: auxiliaryTopRightArea?.width)
    }
}

/// A resident projector above every app: non-activating, on every Space,
/// never the main window. One fixed canvas under the notch; the pointer
/// passes through it everywhere except over the shape.
public final class IslandPanel: NSPanel {
    public let geometry: IslandGeometry
    private let onHover: @MainActor (Bool) -> Void
    private var shape: CGRect = .zero
    private var hitSize: CGSize = .zero
    /// What the view was last asked to show, so a new notch can re-derive it.
    private var presented: (size: IslandState.Size, contentHeight: CGFloat) = (.hidden, 0)
    /// What currently takes clicks; read by tests.
    var hitArea: CGSize { hitSize }
    private var shrinkTask: Task<Void, Never>?
    private var hovering = false
    /// Whether the session was told; the peek alone never tells it.
    private var hoverSent = false
    private var dwellTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?

    public init<Content: View>(
        content: Content, geometry: IslandGeometry, onHover: @escaping @MainActor (Bool) -> Void
    ) {
        self.geometry = geometry
        self.onHover = onHover
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: IslandChrome.canvasWidth,
                                                            height: IslandChrome.canvasHeight)),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: false)
        // Above the menu bar: the shape continues the notch, which sits in it.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
        redock()
        watchPointer()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.redock() }
        }
    }

    isolated deinit {
        monitors.forEach(NSEvent.removeMonitor)
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    /// The shape the view is heading to. Hidden means ordered out; the hold
    /// key still works without a window.
    public func present(size: IslandState.Size, contentHeight: CGFloat) {
        shrinkTask?.cancel()
        presented = (size, contentHeight)
        guard size != .hidden else {
            // Nothing is on screen: nothing takes clicks, nothing is hovered,
            // and the next opening starts from zero rather than a size nobody saw.
            orderOut(nil)
            endHover()
            setHit(.zero)
            return
        }
        let target = IslandChrome.shapeSize(for: size, contentHeight: contentHeight, notch: geometry.notch)
        let sizes = IslandChrome.hitSizes(current: hitSize, target: target)
        setHit(sizes.now)
        if let later = sizes.later {
            shrinkTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(IslandChrome.hitShrinkDelay)) } catch { return }
                self?.setHit(later)
            }
        }
        if !isVisible { orderFrontRegardless() }
    }

    private func setHit(_ size: CGSize) {
        hitSize = size
        reshape()
        track(NSEvent.mouseLocation)
    }

    private func reshape() {
        shape = IslandChrome.shapeRect(
            IslandChrome.hitSize(base: hitSize, peeking: geometry.peeking,
                                 resting: IslandMotion.rests(presented.size), notch: geometry.notch),
            notch: geometry.notch)
    }

    /// The display with the notch, or the one with the menu bar. Never
    /// animated: the canvas is placed once per display change.
    private func redock() {
        let screens = NSScreen.screens
        guard let index = NotchGeometry.pick(screens.map(\.islandShape)) else { return }
        renotch(NotchGeometry.notch(on: screens[index].islandShape))
    }

    /// Menu-bar icons coming and going change the notch too: the click area
    /// is re-derived for the new one, never kept from the old (security
    /// review 16i-1, HIGH).
    func renotch(_ notch: Notch) {
        geometry.notch = notch
        setFrame(IslandChrome.canvasFrame(for: notch), display: true)
        shrinkTask?.cancel()
        let size = presented.size
        setHit(size == .hidden ? .zero
            : IslandChrome.shapeSize(for: size, contentHeight: presented.contentHeight, notch: notch))
    }

    /// Mouse-moved goes to the active app, which is rarely this one: the
    /// global monitor sees it then, the local one when Companion is in front.
    private func watchPointer() {
        let kinds: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: kinds, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.track(NSEvent.mouseLocation) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: kinds, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.track(NSEvent.mouseLocation) }
            return event
        }) { monitors.append(local) }
    }

    /// Clicks pass through the canvas at once when the pointer leaves the
    /// shape; hover ends a beat later, so crossing an edge does not flicker.
    /// Entering, the notch peeks at once and the session hears of it only
    /// if the pointer stays (spec 16i §11).
    func track(_ point: CGPoint) {
        let portal = geometry.portal.map { IslandChrome.portalScreenRect($0, canvas: frame) }
        let inside = isVisible && IslandChrome.pointerInside(point, shape: shape, portal: portal)
        ignoresMouseEvents = IslandChrome.ignoresPointer(inside: inside, isKey: isKeyWindow)
        if inside {
            leaveTask?.cancel()
            leaveTask = nil
            guard !hovering else { return }
            hovering = true
            setPeeking(true)
            dwellTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(IslandMotion.peekDwell)) } catch { return }
                // A pointer already on its way out does not open anything.
                guard let self, self.hovering, self.leaveTask == nil, !self.hoverSent else { return }
                self.hoverSent = true
                self.onHover(true)
            }
        } else if hovering, leaveTask == nil {
            leaveTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(MotionTime.fast)) } catch { return }
                guard let self else { return }
                self.leaveTask = nil
                guard self.hovering else { return }
                self.endHover()
            }
        }
    }

    private func endHover() {
        leaveTask?.cancel()
        leaveTask = nil
        dwellTask?.cancel()
        hovering = false
        setPeeking(false)
        guard hoverSent else { return }
        hoverSent = false
        onHover(false)
    }

    private func setPeeking(_ peeking: Bool) {
        guard geometry.peeking != peeking else { return }
        geometry.peeking = peeking
        reshape()
    }

    /// The field needs the keyboard (16e). Non-activating plus
    /// `becomesKeyOnlyIfNeeded`: only a click in the field makes it key, and
    /// the app in front stays the active app.
    public override var canBecomeKey: Bool { true }

    /// Told when another app takes the keyboard (a click elsewhere): the
    /// field would otherwise stay focused and the panel open over that app.
    public var onResignKey: (() -> Void)?

    public override func resignKey() {
        super.resignKey()
        onResignKey?()
        track(NSEvent.mouseLocation)
    }

    /// Gives the keyboard back to the app in front: ordering a key panel out
    /// returns key status to the active app's window.
    public func releaseKey() {
        guard isKeyWindow else { return }
        orderOut(nil)
        orderFrontRegardless()
    }

    public override var canBecomeMain: Bool { false }
}
