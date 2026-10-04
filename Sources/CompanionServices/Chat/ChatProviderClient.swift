import CompanionCore
import Foundation

package final class ChatProviderClient: ChatProvider, Sendable {
    private let secrets: any SecretStore
    private let probe: any CapabilityProbe
    private let transport: any ChatTransport
    private let settings: ChatSettings
    private let ownerFirstName: String
    private let ownerAbout: String
    private let ownerInstructions: String
    /// Read at REQUEST time: the profile edited in Settings must reach
    /// the very next message, not the next app launch. The stored
    /// strings above stay as the test-friendly fallback.
    private let profileSource:
        (@Sendable () -> (name: String, about: String, instructions: String))?
    /// Read at request time too: switching language in Settings has to reach
    /// the next message, not the next launch.
    private let languageSource: (@Sendable () -> AppLanguage)?
    /// The resolved Speaking language, read per request like the language;
    /// only the hold's voice prompt uses it.
    private let speakingSource: (@Sendable () -> String)?
    /// Read at request time, like the profile: memory written at the close of
    /// one session must reach the very next message (9j-2).
    private let memorySource: (@Sendable () -> String)?
    /// The skills catalog, read per request like memory (Wave 11a).
    private let skillsSource: (@Sendable () -> String)?
    private let catalog: [ProviderDescriptor]
    /// Read at REQUEST time, like the profile and the language above: which
    /// local models exist is a fact about the machine that changes while the
    /// app is open, and a catalog frozen at launch would keep offering a model
    /// the user deleted.
    private let catalogSource: (@Sendable () -> [ProviderDescriptor])?
    private let resolveAttachment: (@Sendable (AttachmentRef) -> AttachmentPayload?)?
    /// Injectable so a test does not sit through a real backoff. The retry is
    /// the behaviour under test; the waiting is not.
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    /// Wave 15c-7: the hold's fast brain passes 1. Its backoff on a 429 was
    /// the 8-24 s turns measured live; the next provider answers sooner than
    /// any wait could.
    private let maxAttempts: Int
    /// Wave 15d-9: the hold's clients ask for the voice rules; the typed
    /// chat's client keeps the default and its prompt stays as it was.
    private let voice: Bool

    package init(
        secrets: any SecretStore,
        probe: any CapabilityProbe,
        transport: any ChatTransport,
        settings: ChatSettings = .default,
        ownerFirstName: String = "",
        ownerAbout: String = "",
        ownerInstructions: String = "",
        profileSource: (@Sendable () -> (name: String, about: String, instructions: String))? = nil,
        languageSource: (@Sendable () -> AppLanguage)? = nil,
        speakingSource: (@Sendable () -> String)? = nil,
        memorySource: (@Sendable () -> String)? = nil,
        skillsSource: (@Sendable () -> String)? = nil,
        catalog: [ProviderDescriptor] = ProviderDescriptor.catalog,
        catalogSource: (@Sendable () -> [ProviderDescriptor])? = nil,
        resolveAttachment: (@Sendable (AttachmentRef) -> AttachmentPayload?)? = nil,
        sleep: (@Sendable (TimeInterval) async throws -> Void)? = nil,
        maxAttempts: Int = RetryPolicy.maxAttempts,
        voice: Bool = false
    ) {
        self.maxAttempts = maxAttempts
        self.voice = voice
        self.secrets = secrets
        self.probe = probe
        self.transport = transport
        self.settings = settings
        self.ownerFirstName = ownerFirstName
        self.ownerAbout = ownerAbout
        self.ownerInstructions = ownerInstructions
        self.profileSource = profileSource
        self.languageSource = languageSource
        self.speakingSource = speakingSource
        self.memorySource = memorySource
        self.skillsSource = skillsSource
        self.catalog = catalog
        self.catalogSource = catalogSource
        self.resolveAttachment = resolveAttachment
        self.sleep = sleep ?? { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }

    package func stream(_ history: [Turn], tools: [ToolSpec])
        -> AsyncThrowingStream<ChatDelta, Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.route(
                    history: history, tools: tools, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    package func verify(_ key: String, provider: ProviderDescriptor) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ChatError.invalidKey }
        guard let url = URL(string: provider.baseURL.absoluteString + "/models")
        else { throw ChatError.unreachable }
        // Validate endpoint URL against security policy.
        guard EndpointPolicy.isAcceptable(url) else { throw ChatError.unreachable }

        var request = URLRequest(
            url: url, timeoutInterval: settings.inactivityTimeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")

        let response: HTTPURLResponse
        do {
            (_, response) = try await transport.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw ChatError.timeout
        } catch {
            throw ChatError.unreachable
        }
        if response.statusCode == 200 { return }
        throw ChatSSEAttempt.mapStatus(response.statusCode)
    }

    private func route(
        history: [Turn],
        tools: [ToolSpec],
        continuation: AsyncThrowingStream<ChatDelta, Error>.Continuation
    ) async {
        let providers = ProviderDescriptor.route(
            order: settings.providerOrder,
            catalog: catalogSource?() ?? catalog)
        do {
            var lastError: ChatError?
            var attempted = false
            providerLoop: for provider in providers {
                try Task.checkCancellation()
                if provider.secretKey != nil, storedKey(for: provider) == nil {
                    continue
                }
                if !(await probe.isAvailable(provider)) { continue }
                attempted = true
                let name: String
                let about: String
                let instructions: String
                if let live = profileSource?() {
                    name = live.name
                    about = live.about
                    instructions = live.instructions
                } else {
                    name = ownerFirstName
                    about = ownerAbout
                    instructions = ownerInstructions
                }
                // Attempts against THIS provider before demoting it. A 429 or
                // a timeout used to drop straight down the ladder, and with
                // nothing below it the user was told there was no provider —
                // a burst of traffic reported as a broken setup.
                var attempt = 1
                while true {
                    try Task.checkCancellation()
                    let outcome = await ChatSSEAttempt.run(
                        provider: provider,
                        key: storedKey(for: provider),
                        history: history,
                        tools: tools,
                        settings: settings,
                        ownerFirstName: name,
                        about: about,
                        instructions: instructions,
                        language: languageSource?() ?? .en,
                        memory: memorySource?() ?? "",
                        skills: skillsSource?() ?? "",
                        voice: voice,
                        speaking: speakingSource?(),
                        transport: transport,
                        resolveAttachment: resolveAttachment,
                        yield: { continuation.yield($0) })
                    switch outcome {
                    case .cancelled:
                        continuation.finish(throwing: CancellationError())
                        return
                    case .reply, .spokePartial, .handoff:
                        // 15c-0: the ladder's own log used to be decorative
                        // (`lastStack` nobody read) — this is who actually
                        // answered, never the words (DM1c-1 §8).
                        Log.chat("chat: answered by \(provider.id)/\(provider.model)")
                        continuation.finish()
                        return
                    case .failed(let error):
                        // The ladder's misses were invisible: a turn that
                        // every provider rejected ended "completed" with no
                        // trace of who refused what (QA 16k-3). The error's
                        // identity only, never the words.
                        Log.chat("chat: \(provider.id)/\(provider.model) failed \(error)")
                        lastError = error
                        guard attempt < maxAttempts,
                              RetryPolicy.shouldRetry(error, attempt: attempt)
                        else { continue providerLoop }
                        attempt += 1
                        do {
                            try await sleep(
                                RetryPolicy.delay(attempt: attempt))
                        } catch {
                            continuation.finish(
                                throwing: CancellationError())
                            return
                        }
                    }
                }
            }
            continuation.finish(
                throwing: attempted ? (lastError ?? .noProvider) : .noProvider)
        } catch is CancellationError {
            continuation.finish(throwing: CancellationError())
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func storedKey(for provider: ProviderDescriptor) -> String? {
        guard let name = provider.secretKey else { return nil }
        let value: String?
        do {
            value = try secrets.read(name)
        } catch {
            return nil
        }
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
