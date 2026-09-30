import CompanionCore
import Foundation

/// How the app decides which door to open. Split out of `ChatViewModel` for
/// the same reason as jobs and attachments: one screen's worth of state per
/// file, so the view model stays readable.
extension ChatViewModel {
    package func onAppear() {
        do {
            let raw = try secrets.read(.openAI)
            let key = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !key.isEmpty {
                startup = .premium
                needsOnboarding = false
                loadRecentOrReport()
                return
            }
        } catch {
            // A keychain that says no is a reason to look for a local path,
            // not a reason to give up: the error is shown, the probe still runs.
            errorText = ChatCopy.error(error)
        }
        beginProbe()
    }

    /// Asynchronous by necessity — a daemon has to be asked — and that is why
    /// `probing` exists as a state instead of a spinner over a half-built UI.
    /// The 2 s cap the spec asks for is owned by the adapter's own timeout:
    /// a second timer here would only duplicate it.
    /// "Ya instalé Ollama": probe again without relaunching the app.
    package func retryLocalProbe() {
        beginProbe()
    }

    private func beginProbe() {
        probeTask?.cancel()
        needsOnboarding = true
        startup = .probing
        guard let startupProbe else {
            startup = .none
            return
        }
        let saved = ProviderPreference.acceptedPath
        probeTask = Task { [weak self] in
            let paths = await startupProbe.probe(preferred: saved?.model)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.finishProbe(paths, saved: saved) }
        }
    }

    private func finishProbe(_ paths: [LocalPath], saved: LocalPath?) {
        startup = paths.isEmpty ? .none : .base(paths)
        // Only a saved path the probe just saw alive skips the screen. One the
        // user deleted between launches must not unlock an app that cannot talk.
        guard let saved, paths.contains(saved) else { return }
        acceptLocalBase(saved)
    }

    /// Confirms a path the probe already found; it never probes again, and it
    /// never goes out to the network to validate a key that does not exist.
    package func acceptLocalBase(_ path: LocalPath) {
        acceptedLocal = path
        ProviderPreference.accept(path)
        needsOnboarding = false
        errorText = nil
        loadRecentOrReport()
    }

    private func loadRecentOrReport() {
        do {
            try loadMostRecent()
        } catch {
            errorText = ChatCopy.error(error)
        }
    }
}
