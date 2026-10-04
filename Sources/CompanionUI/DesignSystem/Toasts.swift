import CompanionCore
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
package final class NoticeCenter {
    package private(set) var queue = NoticeQueue()
    private let sound: (any InterfaceSounding)?
    private let now: () -> TimeInterval

    package init(
        sound: (any InterfaceSounding)? = nil,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) {
        self.sound = sound
        self.now = now
    }

    package func toast(_ text: String, level: NoticeLevel = .info) {
        queue.add(text, level: level, at: now())
        sound?.play(SoundCue.forLevel(level))
    }

    package func tick(at time: TimeInterval? = nil) {
        queue.expire(at: time ?? now())
    }
}

/// The chip the info toast already uses. Error is the same shape; only the
/// tone changes, because a second layout would read as a different control.
enum ToastChrome {
    enum Tone: Equatable {
        case accent
        case danger
    }

    static func tone(_ level: NoticeLevel) -> Tone {
        level == .error ? .danger : .accent
    }

    static func fill(_ level: NoticeLevel) -> Color {
        switch level {
        case .error: Semantic.destructive
        case .info: Semantic.accent
        }
    }

    /// The chip is filled, so the ink is the contrast pair of that fill.
    static func ink(_ level: NoticeLevel) -> Color {
        switch level {
        case .error: Semantic.destructiveForeground
        case .info: Semantic.accentForeground
        }
    }

    /// Arc's error toast speaks its type before the copy. The info chip was
    /// never announced; adding one would speak every confirm twice.
    static func announcement(_ notice: Notice, language: AppLanguage = Localized.language()) -> String? {
        guard tone(notice.level) == .danger else { return nil }
        let prefix = Localized.string("notices.error.prefix", language: language)
        return "\(prefix): \(spoken(notice.text))"
    }

    /// Longest copy VoiceOver is handed; the chip itself stays at two lines.
    static let announcementLimit = 160

    /// Notice text can quote a tool or a page, so it is spoken as one line
    /// without control, format or bidi scalars that could reorder or hide it.
    static func spoken(_ text: String) -> String {
        let oneLine = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let plain = ApprovalCopy.plainPreview(oneLine, keepingLayout: false)
        guard plain.count > announcementLimit else { return plain }
        return plain.prefix(announcementLimit) + "…"
    }
}

/// Same curve as the info toast. Reduced motion keeps a short fade and
/// drops the slide: the chip changes in place, it does not cross the screen.
enum ToastMotion {
    enum Kind: Equatable {
        case slideAndFade
        case fade
    }

    static func kind(reduceMotion: Bool) -> Kind {
        reduceMotion ? .fade : .slideAndFade
    }

    static func transition(reduceMotion: Bool) -> AnyTransition {
        switch kind(reduceMotion: reduceMotion) {
        case .slideAndFade: .move(edge: .trailing).combined(with: .opacity)
        case .fade: .opacity
        }
    }

    static func animation(reduceMotion: Bool) -> Animation? {
        // Linear and short, the house reduced-motion fade: nothing moves, so
        // there is no travel for an ease to shape, but the opacity still lands softly.
        reduceMotion ? MotionCurve.animation(MotionCurve.linear, MotionTime.fast) : .expoOut(MotionTime.fast)
    }
}

struct ToastStack: View {
    var center: NoticeCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            VStack(alignment: .trailing, spacing: Space.x2) {
                ForEach(center.queue.visible) { notice in
                    Text(notice.text)
                        .font(.uiCaption)
                        .foregroundStyle(ToastChrome.ink(notice.level))
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, Space.x3)
                        .padding(.vertical, Space.x2)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .fill(ToastChrome.fill(notice.level))
                        )
                        .transition(ToastMotion.transition(reduceMotion: reduceMotion))
                        .onAppear {
                            guard let line = ToastChrome.announcement(notice) else { return }
                            AccessibilityNotification.Announcement(line).post()
                        }
                }
            }
            .animation(
                ToastMotion.animation(reduceMotion: reduceMotion),
                value: center.queue.visible.map(\.id))
            .onChange(of: context.date) { _, date in
                center.tick(at: date.timeIntervalSince1970)
            }
        }
        .frame(maxWidth: 280, alignment: .trailing)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Localized.string("notices.label"))
    }
}
