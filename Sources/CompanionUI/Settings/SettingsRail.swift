import CompanionCore
import SwiftUI

// S1b of the Settings brief (ajustes-hoja-incredible): the sheet's rail, as
// Incredible draws it. Values come from the local reference
// [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967].

package enum SettingsRailMetrics {
    package static let width: CGFloat = 236
    package static let paddingTop: CGFloat = Space.x3
    package static let paddingBottom: CGFloat = Space.x4
    package static let searchPaddingX: CGFloat = Space.x3
    package static let searchPaddingBottom: CGFloat = Space.x6
    package static let groupGap: CGFloat = Space.x7
    package static let rowHeight: CGFloat = Space.x9
    package static let rowGap: CGFloat = Space.x2_5
    package static let rowPaddingX: CGFloat = Space.x2_5
    package static let rowRadius: CGFloat = Radius.chip
    package static let iconSize: CGFloat = 18
    package static let rowFontSize: CGFloat = TypeSize.rowTitle
    package static let hoverDuration = 0.15
    package static let headingPaddingX: CGFloat = Space.x2_5
    package static let headingPaddingBottom: CGFloat = Space.x1_5
    package static let footerPaddingX: CGFloat = 22
    package static let footerPaddingTop: CGFloat = Space.x2
    package static let maxResults = 8
}

extension SettingsTab {
    /// Incredible's first group has no heading; only "Account" is labelled.
    package static var groups: [(heading: String?, pages: [SettingsTab])] {
        [(nil, firstGroup), (Localized.string("settings.group.account"), secondGroup)]
    }
}

/// Where the arrow keys stand in the search results. Pure, so the keyboard
/// rules are tested without a window.
package struct SettingsSearchCursor: Equatable {
    package private(set) var index = 0

    package init() {}

    /// Clamped at both ends: the list does not wrap.
    package mutating func move(by delta: Int, count: Int) {
        index = count > 0 ? min(max(index + delta, 0), count - 1) : 0
    }

    /// The results can shrink under a cursor that stayed put.
    package func pick(count: Int) -> Int? {
        count > 0 ? min(index, count - 1) : nil
    }

    package mutating func point(at row: Int, count: Int) {
        guard row >= 0, row < count else { return }
        index = row
    }

    package mutating func reset() { index = 0 }

    /// True when the field consumed the key. Esc clears typed text, but a
    /// pending tool approval owns Esc first (the root denies it), and an
    /// empty field lets Esc reach the sheet.
    package mutating func handle(_ key: KeyEquivalent, count: Int, query: inout String,
                                 approvalPending: Bool) -> Bool {
        switch key {
        case .downArrow: move(by: 1, count: count)
        case .upArrow: move(by: -1, count: count)
        case .escape:
            guard !approvalPending, !query.isEmpty else { return false }
            query = ""
        default: return false
        }
        return true
    }
}

/// Search on top, the pages in two groups, the version at the bottom.
struct SettingsSidebar: View {
    @Binding var tab: SettingsTab
    @Binding var query: String
    let onPick: (SettingsSearch.Entry) -> Void
    var approvalPending = false
    @State private var cursor = SettingsSearchCursor()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.none) {
            SettingsSearchField(query: $query, onSubmit: submit, onKey: key)
                .padding(.horizontal, SettingsRailMetrics.searchPaddingX)
                .padding(.bottom, SettingsRailMetrics.searchPaddingBottom)
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                pages
            } else {
                SettingsSearchResults(query: query, selected: cursor.index,
                                      onHover: { cursor.point(at: $0, count: SettingsSearchResults.rows(for: query).count) },
                                      onPick: pick)
                    .padding(.horizontal, SettingsRailMetrics.searchPaddingX)
            }
            Spacer(minLength: Space.none)
            Text(String(format: Localized.string("settings.sidebar.version"), SettingsVersion.current))
                .font(Fonts.sans(TypeSize.caption).weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Semantic.mutedForeground)
                .textSelection(.enabled)
                .padding(.horizontal, SettingsRailMetrics.footerPaddingX)
                .padding(.top, SettingsRailMetrics.footerPaddingTop)
        }
        .padding(.top, SettingsRailMetrics.paddingTop)
        .padding(.bottom, SettingsRailMetrics.paddingBottom)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Semantic.surfaceSecondary)
        .onChange(of: query) { cursor.reset() }
    }

    private var pages: some View {
        VStack(alignment: .leading, spacing: Space.none) {
            ForEach(Array(SettingsTab.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { Spacer().frame(height: SettingsRailMetrics.groupGap) }
                if let heading = group.heading {
                    Text(heading)
                        .font(Fonts.sans(TypeSize.caption).weight(.medium))
                        .foregroundStyle(Semantic.mutedForeground)
                        .padding(.horizontal, SettingsRailMetrics.headingPaddingX)
                        .padding(.bottom, SettingsRailMetrics.headingPaddingBottom)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(group.pages, id: \.self) { page in
                    SettingsRailRow(page: page, selected: tab == page) {
                        withAnimation(ChromeMotion.animation(.springSelect, reduceMotion: reduceMotion)) { tab = page }
                    }
                }
            }
        }
        .padding(.horizontal, SettingsRailMetrics.searchPaddingX)
    }

    private func submit() {
        let rows = SettingsSearchResults.rows(for: query)
        guard let row = cursor.pick(count: rows.count) else { return }
        pick(rows[row].entry)
    }

    private func pick(_ entry: SettingsSearch.Entry) {
        cursor.reset()
        onPick(entry)
    }

    private func key(_ press: KeyEquivalent) -> KeyPress.Result {
        cursor.handle(press, count: SettingsSearchResults.rows(for: query).count, query: &query,
                      approvalPending: approvalPending) ? .handled : .ignored
    }
}

struct SettingsRailRow: View {
    let page: SettingsTab
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsRailMetrics.rowGap) {
                Image(systemName: page.symbol)
                    .frame(width: SettingsRailMetrics.iconSize, height: SettingsRailMetrics.iconSize)
                    .accessibilityHidden(true)
                Text(page.title)
                Spacer(minLength: Space.none)
            }
            .font(Fonts.sans(SettingsRailMetrics.rowFontSize).weight(.medium))
            .foregroundStyle(Semantic.foreground)
            .padding(.horizontal, SettingsRailMetrics.rowPaddingX)
            .frame(height: SettingsRailMetrics.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: SettingsRailMetrics.rowRadius)
                    .fill(selected ? Semantic.sidebarSelected : hovered ? Semantic.hover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over in
            withAnimation(ChromeMotion.animation(
                MotionCurve.animation(MotionCurve.ease, SettingsRailMetrics.hoverDuration),
                reduceMotion: reduceMotion)) { hovered = over }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Search over the settings inventory.
struct SettingsSearchField: View {
    @Binding var query: String
    let onSubmit: () -> Void
    var onKey: (KeyEquivalent) -> KeyPress.Result = { _ in .ignored }

    var body: some View {
        HStack(spacing: Space.x2) {
            Image(systemName: "magnifyingglass")
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .accessibilityHidden(true)
            TextField(Localized.string("settings.search.placeholder"), text: $query)
                .textFieldStyle(.plain)
                .font(.uiLabel)
                .onSubmit(onSubmit)
                .onKeyPress(keys: [.upArrow, .downArrow, .escape]) { onKey($0.key) }
        }
        .padding(.horizontal, Space.x3)
        .padding(.vertical, Space.x2)
        // A text field in a capsule, not a button: CapsuleChipStyle has
        // nothing to style here. The field wash, not `muted`: in dark,
        // `muted` is the rail's own fill and the field vanished into it.
        .background(Capsule().fill(Semantic.fieldWash))
    }
}

struct SettingsSearchResults: View {
    let query: String
    var selected: Int? = nil
    var onHover: (Int) -> Void = { _ in }
    let onPick: (SettingsSearch.Entry) -> Void

    /// One result: the setting and, under it, the page it lives on.
    struct Row {
        let entry: SettingsSearch.Entry
        var title: String { entry.title }
        var page: String { SettingsTab(rawValue: entry.page)?.title ?? "" }

        init(_ entry: SettingsSearch.Entry) { self.entry = entry }
    }

    /// The one list both the view and the keyboard cursor count, so they cannot disagree.
    static func rows(for query: String) -> [Row] {
        SettingsSearch.match(query, in: SettingsInventory.searchEntries)
            .prefix(SettingsRailMetrics.maxResults).map(Row.init)
    }

    static func emptyNote(_ query: String) -> String {
        String(format: Localized.string("settings.search.none"), query)
    }

    @ViewBuilder var body: some View {
        let found = Self.rows(for: query)
        if found.isEmpty {
            Text(Self.emptyNote(query))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .padding(.horizontal, SettingsRailMetrics.rowPaddingX)
        } else {
            ForEach(Array(found.enumerated()), id: \.element.entry.id) { row, result in
                Button { onPick(result.entry) } label: {
                    VStack(alignment: .leading, spacing: Space.none) {
                        Text(result.title)
                            .font(.uiLabel)
                            .foregroundStyle(Semantic.foreground)
                            .lineLimit(1)
                        Text(result.page)
                            .font(.uiCaption)
                            .foregroundStyle(Semantic.mutedForeground)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SettingsRailMetrics.rowPaddingX)
                    .padding(.vertical, Space.x1)
                    .background(
                        RoundedRectangle(cornerRadius: SettingsRailMetrics.rowRadius)
                            .fill(row == selected ? Semantic.hover : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { onHover(row) } }
                .accessibilityAddTraits(row == selected ? .isSelected : [])
            }
        }
    }
}
