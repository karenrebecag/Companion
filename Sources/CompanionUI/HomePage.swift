import CompanionCore
import SwiftUI

/// Incredible's Home (spec 16j §8): a greeting, the "hold fn" card, the
/// first steps, and the tasks by day. No chat field: talking happens in the
/// island.
struct HomePage: View {
    var chat: ChatViewModel
    let onOpen: (ConversationMeta) -> Void
    let onSettings: (SettingsTab) -> Void

    var body: some View {
        // 16n: Incredible's Home — a 98 pt head, a 1300 column, 40 pt sides.
        ScrollView {
            VStack(alignment: .leading, spacing: Space.none) {
                Text(greeting)
                    .font(Fonts.sans(TypeSize.dialogTitle).weight(.semibold))
                    .tracking(Tracking.title, at: TypeSize.dialogTitle)
                    .foregroundStyle(Semantic.foreground)
                    .padding(.top, HomeMetrics.headTop)
                    .frame(height: HomeMetrics.headHeight, alignment: .center)
                HStack(alignment: .top, spacing: HomeMetrics.columnGap) {
                    VStack(alignment: .leading, spacing: HomeMetrics.tasksTop) {
                        if let error = ChatErrorSurface.visible(
                            errorText: chat.errorText, needsOnboarding: chat.needsOnboarding, dismissed: nil)
                        {
                            HomeErrorBanner(text: error, onDismiss: chat.dismissError)
                        }
                        hero
                        tasks
                    }
                    .frame(maxWidth: .infinity)
                    HomeStartCard(talked: !chat.recents.isEmpty, profiled: !UserProfile.ownerName.isEmpty,
                                  onProfile: { onSettings(.you) })
                        .frame(width: HomeMetrics.sideColumn)
                }
            }
            .frame(maxWidth: HomeMetrics.maxWidth, alignment: .leading)
            .padding(.horizontal, HomeMetrics.paddingX)
            .padding(.bottom, HomeMetrics.paddingBottom)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var greeting: String {
        let name = UserProfile.ownerName.split(separator: " ").first.map(String.init) ?? ""
        return name.isEmpty ? Localized.string("home.welcome.anon")
            : String(format: Localized.string("home.welcome"), name)
    }

    // Incredible lays a photo over the right 56 %; ours has none yet, so the
    // ink ground carries it alone.
    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            HStack(spacing: Space.x2) {
                Text(Localized.string("home.hero.before"))
                BrandKeycapView(text: "fn", titleSize: TypeSize.bannerTitle)
                Text(Localized.string("home.hero.after"))
            }
            .font(Fonts.sans(TypeSize.bannerTitle).weight(.semibold))
            .tracking(Tracking.title, at: TypeSize.bannerTitle)
            .foregroundStyle(Neutral.white.color)
            Text(Localized.string("home.hero.body"))
                .typeRole(.heroBody)
                .foregroundStyle(Neutral.white.color.opacity(HeroMetrics.bodyAlpha))
                .frame(maxWidth: HeroMetrics.bodyWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, HeroMetrics.paddingX)
        .padding(.vertical, HeroMetrics.paddingY + Space.x2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HeroMetrics.radius).fill(HeroMetrics.ink.color))
    }

    @ViewBuilder
    private var tasks: some View {
        let sections = HomeTasks.sections(chat.recents, now: Date(), calendar: .current)
        if sections.isEmpty {
            Text(Localized.string("home.empty"))
                .font(.uiBody)
                .foregroundStyle(Semantic.mutedForeground)
        }
        VStack(alignment: .leading, spacing: HomeMetrics.groupGap) {
            ForEach(sections, id: \.day) { section in
                VStack(alignment: .leading, spacing: Space.x2) {
                    Text(Localized.string(HomeCopy.dayKey(section.day)))
                        .font(Fonts.sans(TypeSize.body).weight(.medium))
                        .foregroundStyle(Semantic.textMuted)
                        .padding(.top, Space.x1)
                    VStack(spacing: Space.none) {
                        ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, task in
                            if index > 0 {
                                Rectangle().fill(Semantic.hover)
                                    .frame(height: Stroke.hairline)
                                    .padding(.horizontal, TaskRowMetrics.dividerInset)
                            }
                            HomeTaskRow(task: task) { onOpen(task) }
                        }
                    }
                    .padding(.vertical, TaskRowMetrics.listPaddingY)
                    .background(Semantic.surface)
                    .clipShape(RoundedRectangle(cornerRadius: TaskRowMetrics.listRadius))
                    .overlay(RoundedRectangle(cornerRadius: TaskRowMetrics.listRadius)
                        .strokeBorder(Semantic.borderChrome, lineWidth: Stroke.hairline))
                    .elevation(.hover)
                }
            }
        }
    }
}

enum HomeCopy {
    static func dayKey(_ day: HomeTasks.Day) -> String {
        switch day {
        case .today: "home.day.today"
        case .yesterday: "home.day.yesterday"
        case .earlier: "home.day.earlier"
        }
    }

    static func ago(_ date: Date, now: Date = Date()) -> String {
        switch HomeTasks.ago(date, now: now) {
        case .justNow: Localized.string("home.ago.now")
        case .minutes(let n): String(format: Localized.string("home.ago.minutes"), n)
        case .hours(let n): String(format: Localized.string("home.ago.hours"), n)
        case .days(let n): String(format: Localized.string("home.ago.days"), n)
        }
    }
}

struct HomeTaskRow: View {
    let task: ConversationMeta
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            // 16n: Incredible's history row — 14 pt medium title, the round
            // chat icon, the time and a bare chevron; the row washes 5 %.
            HStack(spacing: TaskRowMetrics.gap) {
                VStack(alignment: .leading, spacing: Space.x2) {
                    Text(task.title)
                        .font(Fonts.sans(TypeSize.rowTitle).weight(.medium))
                        .foregroundStyle(Semantic.foreground)
                        .lineLimit(1)
                    TaskChipIcon()
                }
                Spacer(minLength: Space.x3)
                Text(HomeCopy.ago(task.updatedAt))
                    .font(Fonts.sans(TypeSize.caption))
                    .monospacedDigit()
                    .foregroundStyle(Semantic.textMuted)
                Image(systemName: "chevron.right")
                    .font(Fonts.sans(TaskRowMetrics.chevron * 0.75).weight(.medium))
                    .frame(width: TaskRowMetrics.chevron, height: TaskRowMetrics.chevron)
                    .foregroundStyle(hovering ? Semantic.mutedForeground : Semantic.faintForeground)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, TaskRowMetrics.paddingX)
            .padding(.vertical, TaskRowMetrics.paddingY)
            .background(hovering ? Semantic.hover : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(MotionCurve.animation(MotionCurve.standard, MotionTime.fast), value: hovering)
    }
}

/// "Get Started" with the steps Companion can check today.
struct HomeStartCard: View {
    let talked: Bool
    let profiled: Bool
    let onProfile: () -> Void

    var body: some View {
        // 16l-3: Incredible's action card, its halo in the island's green.
        ActionCard(accent: Semantic.successMuted) {
            HStack {
                Text(Localized.string("home.start.title")).font(.uiLabel.weight(.semibold))
                Spacer()
                Text(String(format: Localized.string("home.start.count"), done, 2))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
            step(1, Localized.string("home.start.talk"), Localized.string("home.start.talk.body"), talked)
            Button(action: onProfile) {
                step(2, Localized.string("home.start.profile"), Localized.string("home.start.profile.body"), profiled)
            }
            .buttonStyle(.plain)
        }
    }

    private var done: Int { (talked ? 1 : 0) + (profiled ? 1 : 0) }

    private func step(_ number: Int, _ title: String, _ body: String, _ complete: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.x2) {
            Image(systemName: complete ? "checkmark.circle.fill" : "\(number).circle")
                .font(.uiLabel)
                .foregroundStyle(complete ? IslandInk.green : Semantic.mutedForeground)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(title).font(.uiLabel).foregroundStyle(Semantic.foreground)
                Text(body)
                    .typeRole(.micro)
                    .foregroundStyle(Semantic.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.none)
        }
        .contentShape(Rectangle())
    }
}
