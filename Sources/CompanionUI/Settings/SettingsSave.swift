import CompanionCore
import SwiftUI

// local reference; brief ajustes-hoja-incredible S3

/// Which save may raise the notice. The set is closed so a control that is
/// not listed cannot grow a default that announces.
enum SettingsSaveKind: Equatable, Sendable {
    case name, profile, microphone, launchAtLogin, volume, diagnostics, voice
    case muteVoice, muteSystemSounds, muteWhileTalking, modelTier, wakeWord, passive

    var announces: Bool {
        switch self {
        case .name, .profile, .microphone, .launchAtLogin, .volume, .diagnostics, .voice:
            true
        case .muteVoice, .muteSystemSounds, .muteWhileTalking, .modelTier, .wakeWord, .passive:
            false
        }
    }
}

/// Visibility of the save notice. A test fires a deadline it was given,
/// so the decision does not read the clock.
struct SettingsSaveNotice: Equatable {
    var visible = false
    var deadlines: [Date] = []

    static let duration: TimeInterval = 1.2
    static let animates = false
    static let radius = Radius.chip
    /// Popup shadow, the brief's ask. It is the same rank the sheet wears as
    /// its modal one; the notice sits outside the sheet's clip so it shows.
    static let elevation = Elevation.popover
    static let inset = Space.x4
    static let padX = Space.x3_5
    static let padY = Space.x2

    mutating func show(at now: Date) -> Date {
        let deadline = now.addingTimeInterval(Self.duration)
        deadlines.append(deadline)
        visible = true
        return deadline
    }

    /// Hides even when a later deadline is still stored. The earlier timer
    /// is left running, so two saves in a row disappear on the first one.
    mutating func fire(deadline: Date) {
        if let index = deadlines.firstIndex(of: deadline) {
            deadlines.remove(at: index)
        }
        visible = false
    }
}

/// Optimistic value plus the generation that owns the in-flight write.
/// A late failure must not roll back a newer edit.
struct SettingsSaveSlot<Value: Equatable>: Equatable {
    struct Token: Equatable {
        fileprivate let generation: Int
    }

    var committed: Value
    var shown: Value
    var saving = false
    var error: String?
    /// A write stuck and nobody has been told yet. Text fields persist on every
    /// keystroke but announce once, when editing ends.
    fileprivate(set) var unannounced = false
    /// A failure was already spoken in this editing session, so the next
    /// keystrokes that fail stay quiet; the row keeps showing the error.
    fileprivate(set) var failureSpoken = false
    private var generation = 0

    init(committed: Value) {
        self.committed = committed
        self.shown = committed
    }

    mutating func begin(_ next: Value) -> Token {
        generation += 1
        shown = next
        saving = true
        error = nil
        return Token(generation: generation)
    }

    mutating func succeed(_ token: Token) -> Bool {
        guard token.generation == generation else { return false }
        committed = shown
        saving = false
        error = nil
        unannounced = true
        return true
    }

    mutating func fail(_ token: Token) -> Bool {
        guard token.generation == generation else { return false }
        shown = committed
        error = SettingsSaveCopy.failed
        saving = false
        return true
    }
}

/// The row shows the error instead of its description, never both.
enum SettingsSaveRow {
    static func subtitle(error: String?, description: String) -> String {
        if let error, !error.isEmpty { return error }
        return description
    }
}

enum SettingsSaveCopy {
    static var saved: String { Localized.string("settings.save.saved") }
    static var failed: String { Localized.string("settings.save.failed") }
}

/// When a successful write raises the notice.
enum SettingsSaveTiming: Equatable {
    case immediate, onEndEditing
}

/// The profile text fields and the notice each one raises. Name is its own
/// group; the rest are profile.
enum SettingsProfileField: CaseIterable {
    case name, city, about, instructions

    var kind: SettingsSaveKind { self == .name ? .name : .profile }

    func write(_ value: String) {
        switch self {
        case .name: UserProfile.ownerName = value
        case .city: UserProfile.city = value
        case .about: UserProfile.about = value
        case .instructions: UserProfile.instructions = value
        }
    }
}

/// What picking an avatar leaves behind: an inline error, or the notice.
struct SettingsAvatarResult: Equatable {
    let error: String?
    let notice: SettingsSaveKind?

    init(saved: Bool) {
        error = saved ? nil : SettingsSaveCopy.failed
        notice = saved ? .profile : nil
    }
}

@MainActor
@Observable
final class SettingsSaveCenter {
    private(set) var notice = SettingsSaveNotice()
    private let now: @MainActor () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let announce: @MainActor (String) -> Void

    /// The seams let a test own the clock, the wait and what VoiceOver hears.
    init(
        now: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        },
        announce: @escaping @MainActor (String) -> Void = { text in
            AccessibilityNotification.Announcement(text).post()
        }
    ) {
        self.now = now
        self.sleep = sleep
        self.announce = announce
    }

    @discardableResult
    func record(_ kind: SettingsSaveKind, at now: Date) -> Date? {
        guard kind.announces else { return nil }
        var next = notice
        let deadline = next.show(at: now)
        notice = next
        return deadline
    }

    func fire(deadline: Date) {
        var next = notice
        next.fire(deadline: deadline)
        notice = next
    }

    /// Arms a hide for this deadline and leaves any earlier one running.
    @discardableResult
    func saved(_ kind: SettingsSaveKind) -> Task<Void, Never>? {
        let start = now()
        guard let deadline = record(kind, at: start) else { return nil }
        announce(SettingsSaveCopy.saved)
        let wait = deadline.timeIntervalSince(start)
        let sleep = sleep
        return Task { @MainActor in
            do { try await sleep(wait) } catch { return }
            self.fire(deadline: deadline)
        }
    }

    /// Writes optimistically. A throwing write reverts the slot and raises no
    /// notice; the write is a closure so the failure path can be driven.
    func commit<Value: Equatable>(
        _ kind: SettingsSaveKind,
        _ slot: inout SettingsSaveSlot<Value>,
        next: Value,
        timing: SettingsSaveTiming = .immediate,
        write: (Value) throws -> Void
    ) {
        guard next != slot.shown || slot.saving else { return }
        let token = slot.begin(next)
        finish(kind, &slot, token, Result { try write(next) }, timing: timing)
    }

    /// The write's outcome, from whichever edit it belongs to. A stale one is
    /// ignored, so an old failure cannot undo or announce over a newer edit.
    func finish<Value: Equatable>(
        _ kind: SettingsSaveKind,
        _ slot: inout SettingsSaveSlot<Value>,
        _ token: SettingsSaveSlot<Value>.Token,
        _ result: Result<Void, Error>,
        timing: SettingsSaveTiming = .immediate
    ) {
        switch result {
        case .success:
            guard slot.succeed(token) else { return }
            if timing == .immediate { endEditing(kind, &slot) }
        case .failure:
            guard slot.fail(token) else { return }
            if timing == .onEndEditing && slot.failureSpoken { return }
            slot.failureSpoken = true
            announce(SettingsSaveCopy.failed)
        }
    }

    func endEditing<Value: Equatable>(_ kind: SettingsSaveKind, _ slot: inout SettingsSaveSlot<Value>) {
        slot.failureSpoken = false
        guard slot.unannounced else { return }
        slot.unannounced = false
        saved(kind)
    }

    /// Returns the inline error for the photo row, nil when it stuck.
    func avatarSet(saved stuck: Bool) -> String? {
        let result = SettingsAvatarResult(saved: stuck)
        if let kind = result.notice { saved(kind) }
        if let error = result.error { announce(error) }
        return result.error
    }

    func updateVoice(
        _ current: VoiceSettings,
        mutate: (inout VoiceSettings) -> Void,
        write: (VoiceSettings) -> Void
    ) -> VoiceSettings {
        var copy = current
        mutate(&copy)
        guard copy != current else { return current }
        write(copy)
        saved(.voice)
        return copy
    }

    func chooseElevenLabs(_ model: ElevenLabsVoiceModel, _ preset: ElevenLabsVoicePreset) {
        settleVoiceChoice(apply: { model.select(preset) }, errorText: { model.errorText })
    }

    func applyElevenLabsCustom(_ model: ElevenLabsVoiceModel) {
        settleVoiceChoice(apply: { model.applyCustom() }, errorText: { model.errorText })
    }

    /// An id the picker already rejected explains itself, in the model's own
    /// catalog copy (never the typed id), and must not also claim the choice
    /// was saved. The model is a closure pair so a test can
    /// drive this without writing the shared voice preference.
    func settleVoiceChoice(apply: () -> Void, errorText: () -> String?) {
        apply()
        if let error = errorText() {
            announce(error)
            return
        }
        saved(.voice)
    }
}

/// Inserted without a transition. A transaction already in flight must not
/// fade the notice in or out.
struct SettingsSaveNoticeOverlay: View {
    let visible: Bool

    var body: some View {
        Group {
            if visible {
                SettingsSaveNoticeChip(text: SettingsSaveCopy.saved)
                    .padding(SettingsSaveNotice.inset)
            }
        }
        .allowsHitTesting(false)
        .animation(SettingsSaveNotice.animates ? Animation.linear : nil, value: visible)
        .transaction { transaction in
            if !SettingsSaveNotice.animates { transaction.animation = nil }
        }
    }
}

struct SettingsSaveNoticeChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Fonts.sans(TypeSize.caption).weight(.medium))
            .foregroundStyle(Semantic.foreground)
            .padding(.horizontal, SettingsSaveNotice.padX)
            .padding(.vertical, SettingsSaveNotice.padY)
            .background(
                RoundedRectangle(cornerRadius: SettingsSaveNotice.radius)
                    .fill(Semantic.surfaceOverlay))
            .elevation(SettingsSaveNotice.elevation)
    }
}
