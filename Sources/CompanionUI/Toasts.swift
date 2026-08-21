import CompanionCore
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
public final class NoticeCenter {
    public private(set) var queue = NoticeQueue()
    private let sound: (any InterfaceSounding)?
    private let now: () -> TimeInterval

    public init(
        sound: (any InterfaceSounding)? = nil,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) {
        self.sound = sound
        self.now = now
    }

    public func toast(_ text: String, level: NoticeLevel = .info) {
        queue.add(text, level: level, at: now())
        sound?.play(SoundCue.forLevel(level))
    }

    public func tick(at time: TimeInterval? = nil) {
        queue.expire(at: time ?? now())
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
                        .foregroundStyle(notice.level == .error
                            ? Semantic.destructiveForeground
                            : Semantic.accentForeground)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, Space.x3)
                        .padding(.vertical, Space.x2)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .fill(notice.level == .error
                                      ? Semantic.destructive : Semantic.accent)
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(
                reduceMotion ? nil : .expoOut(MotionTime.fast),
                value: center.queue.visible.map(\.id))
            .onChange(of: context.date) { _, date in
                center.tick(at: date.timeIntervalSince1970)
            }
        }
        .frame(maxWidth: 280, alignment: .trailing)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Avisos")
    }
}
