import CompanionCore
import SwiftUI

// brief ajustes-hoja-incredible E35: the microphone popup lists the inputs,
// saves the pick, and shows a live level for the chosen one while it is open.

/// The device callback is not on the main actor. This only schedules the
/// model back there; the model itself is touched on the main actor.
nonisolated final class MicHop: @unchecked Sendable {
    nonisolated(unsafe) weak var model: SettingsMicrophoneModel?
    func snapshot(_ snapshot: MicDeviceSnapshot) {
        let model = model
        Task { @MainActor in model?.apply(snapshot) }
    }
    func level(_ value: Double) {
        let model = model
        Task { @MainActor in model?.heard(value) }
    }
}

@Observable
final class SettingsMicrophoneModel {
    private enum ProbeNotice {
        case quiet, blocked, noInput, failed, saveFailed
    }

    /// A probe that stays under this after the warm-up is silence.
    private static let silence = 0.02
    private static let barCount = 6.0

    private(set) var snapshot = MicDeviceSnapshot.empty
    private(set) var preference: MicPreference = .builtIn
    private(set) var resolved = MicChoice.resolve(.builtIn, .empty)
    private(set) var testing = false
    let probeAvailable: Bool
    private var percent = 0.0
    private var notice: ProbeNotice?
    private var peak = 0.0
    private var presented = false
    private var meterTouched = false
    private var watch: (any MicDeviceWatch)?
    private var probeTask: Task<Void, Never>?
    private var quietTask: Task<Void, Never>?
    private var probeGeneration = 0
    private let hop = MicHop()
    private let port: (any MicDevicePort)?
    private let meter: (any MicMeter)?
    private let store: any MicPreferenceStoring
    private let authorized: () -> Bool
    private let quietDelay: Duration

    init(
        port: (any MicDevicePort)? = MicDevices.port,
        meter: (any MicMeter)? = MicDevices.meter,
        store: any MicPreferenceStoring = MicDevices.store,
        authorized: (() -> Bool)? = nil,
        quietDelay: Duration = .milliseconds(1500)
    ) {
        self.port = port
        self.meter = meter
        self.store = store
        self.authorized = authorized ?? { [meter] in meter?.microphoneAuthorized ?? false }
        self.quietDelay = quietDelay
        probeAvailable = meter != nil
        hop.model = self
        reload()
    }

    /// Bars lit out of six, from the smoothed level.
    var litBars: Int {
        Int((min(100, max(0, percent)) / 100 * Self.barCount).rounded())
    }

    /// Only a fault of the probe offers another try; silence and a save that
    /// did not stick are not.
    var canRetry: Bool {
        guard probeAvailable, let notice else { return false }
        return notice != .quiet && notice != .saveFailed
    }

    var noticeText: String? {
        switch notice {
        case nil: nil
        case .quiet: Localized.string("settings.microphone.quiet")
        case .blocked: Localized.string("settings.microphone.blocked")
        case .noInput: Localized.string("settings.microphone.none")
        case .failed: Localized.string("settings.microphone.failed")
        case .saveFailed: Localized.string("settings.microphone.saveFailed")
        }
    }

    /// What the row shows: the current device, by the name the system gives it
    /// now rather than the one stored when it was picked.
    var rowSubtitle: String {
        if let missing = resolved.missingName {
            return String(
                format: Localized.string("settings.microphone.missing.summary"), systemLabel, missing)
        }
        switch preference {
        case .builtIn:
            if snapshot.devices.isEmpty || snapshot.devices.contains(where: \.builtIn) {
                return Localized.string("settings.microphone.builtIn")
            }
            return Localized.string("settings.microphone.system.value")
        case .systemDefault:
            return Localized.string("settings.microphone.system.value")
        case .device(let id, let name):
            return snapshot.devices.first { $0.id == id }?.name ?? name
        }
    }

    func opened() {
        guard !presented else { return }
        presented = true
        reload()
        if watch == nil, let port {
            let hop = hop
            watch = port.watch { hop.snapshot($0) }
        }
        // Opening the popup listens, as the reference does, but never asks:
        // the permission prompt belongs to an action, not to looking.
        if probeAvailable, authorized() { startProbe() }
    }

    func closed() {
        presented = false
        watch?.cancel()
        watch = nil
        stopProbe()
    }

    func choose(_ row: MicMenuRow) {
        guard row.enabled else { return }
        let next: MicPreference
        switch row {
        case .builtIn:
            next = .builtIn
        case .systemDefault:
            next = .systemDefault
        case .device(let id, let name, _):
            if snapshot.devices.first(where: { $0.id == id })?.builtIn == true {
                next = .builtIn
            } else {
                next = .device(id: id, name: name)
            }
        case .missing:
            return
        }
        guard next != preference else { return }
        // Unsaved means the next launch would pick something else: keep what is
        // shown equal to what is stored.
        guard store.save(next) else {
            notice = .saveFailed
            return
        }
        if notice == .saveFailed { notice = nil }
        preference = next
        resolved = MicChoice.resolve(preference, snapshot)
        if listening { startProbe() }
    }

    func retry() {
        guard presented, canRetry else { return }
        startProbe()
    }

    func apply(_ snapshot: MicDeviceSnapshot) {
        let before = MicChoice.route(preference: preference, snapshot: self.snapshot)
        self.snapshot = snapshot
        resolved = MicChoice.resolve(preference, snapshot)
        let after = MicChoice.route(preference: preference, snapshot: snapshot)
        if listening, before != after { startProbe() }
    }

    func heard(_ value: Double) {
        guard testing else { return }
        let level = min(max(value, 0), 1)
        // Same smoothing as the reference: most of the new level, some of the old.
        percent = percent * 0.4 + level * 100 * 0.6
        peak = max(peak, level)
        if peak > Self.silence, notice == .quiet { notice = nil }
    }

    /// A probe is wanted: running, or stopped by a fault the user can fix by
    /// picking another input.
    private var listening: Bool {
        presented && probeAvailable && (testing || canRetry)
    }

    private var systemLabel: String {
        MicRowCopy.title(.systemDefault(
            name: snapshot.systemDefaultName, holding: false, selected: false))
    }

    /// Re-reads the list and the stored choice, e.g. when the page returns.
    func reload() {
        if let snapshot = port?.snapshot() { self.snapshot = snapshot }
        preference = store.load()
        resolved = MicChoice.resolve(preference, snapshot)
    }

    private func startProbe() {
        guard let meter else { return }
        probeGeneration += 1
        let mine = probeGeneration
        meterTouched = true
        testing = true
        percent = 0
        peak = 0
        notice = nil
        quietTask?.cancel()
        probeTask?.cancel()
        let target = resolved.target
        let hop = hop
        let quietDelay = quietDelay
        meter.onLevel { hop.level($0) }
        probeTask = Task { @MainActor [weak self] in
            let fault = await meter.start(target: target)
            // A start that was overtaken says nothing and stops nothing: the
            // newer one owns the shared meter now.
            guard let self, !Task.isCancelled, mine == self.probeGeneration else { return }
            if let fault {
                self.testing = false
                self.percent = 0
                self.notice = Self.notice(for: fault)
                return
            }
            self.quietTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: quietDelay) } catch { return }
                guard let self, mine == self.probeGeneration, self.peak <= Self.silence else { return }
                self.notice = .quiet
            }
        }
    }

    private func stopProbe() {
        probeGeneration += 1
        probeTask?.cancel()
        quietTask?.cancel()
        testing = false
        percent = 0
        notice = nil
        if meterTouched {
            meterTouched = false
            meter?.stop()
        }
    }

    private static func notice(for fault: MicProbeFault) -> ProbeNotice {
        switch fault {
        case .blocked: .blocked
        case .noInput: .noInput
        case .failed: .failed
        }
    }
}
