import CompanionCore
@testable import CompanionUI
import CompanionCoreTestSupport
import Foundation
import Testing

// The Apps setup form, on Arc's input and contact-section bar: errors only
// after the first submit and live after that, a saving state that cannot
// be submitted twice, a failure that keeps what was typed, and a
// confirmation. All of it is decided here, without rendering.

private let goodEndpoint = "https://companion-apps.vercel.app"
private let goodKey = String(repeating: "k", count: 64)
/// AppsModel is MainActor-bound and test arguments are built off it; the
/// table's copy is checked against the model's in `theTableUsesTheModelsMinimum`.
private let minKey = 32

struct EdgeCase: Sendable, CustomTestStringConvertible {
    let name: String
    let endpoint: String
    let key: String
    let valid: Bool
    var testDescription: String { name }

    init(_ name: String, endpoint: String = goodEndpoint, key: String = goodKey, valid: Bool) {
        self.name = name
        self.endpoint = endpoint
        self.key = key
        self.valid = valid
    }
}

private let family = "\u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"

private let edgeCases: [EdgeCase] = [
    EdgeCase("good", valid: true),
    EdgeCase("empty endpoint", endpoint: "", valid: false),
    EdgeCase("http", endpoint: "http://x.vercel.app", valid: false),
    EdgeCase("path", endpoint: "https://x.vercel.app/api", valid: false),
    EdgeCase("padded", endpoint: "  \(goodEndpoint)\n", valid: true),
    EdgeCase("double trailing slash", endpoint: goodEndpoint + "//", valid: true),
    EdgeCase("port", endpoint: goodEndpoint + ":8443", valid: true),
    EdgeCase("empty port (pinned)", endpoint: goodEndpoint + ":", valid: true),
    EdgeCase("letters as port", endpoint: goodEndpoint + ":abc", valid: false),
    EdgeCase("fragment", endpoint: goodEndpoint + "#top", valid: false),
    EdgeCase("dot path", endpoint: goodEndpoint + "/.", valid: false),
    EdgeCase("slash then empty fragment", endpoint: goodEndpoint + "/#", valid: false),
    EdgeCase("uppercase scheme (#227)", endpoint: "HTTPS://X.VERCEL.APP", valid: true),
    EdgeCase("uppercase http", endpoint: "HTTP://X.VERCEL.APP", valid: false),
    EdgeCase("uppercase host", endpoint: "https://X.Vercel.App", valid: true),
    EdgeCase("IDN host (pinned)", endpoint: "https://bücher.example", valid: true),
    EdgeCase("space in host", endpoint: "https://x vercel.app", valid: false),
    EdgeCase("scheme only", endpoint: "https://", valid: false),
    EdgeCase("empty host with path", endpoint: "https:///x", valid: false),
    EdgeCase("IPv4 literal", endpoint: "https://127.0.0.1", valid: true),
    EdgeCase("localhost", endpoint: "https://localhost", valid: true),
    EdgeCase("key one short", key: String(repeating: "k", count: minKey - 1), valid: false),
    EdgeCase("key at the minimum", key: String(repeating: "k", count: minKey), valid: true),
    EdgeCase("padded key one short", key: "  " + String(repeating: "k", count: minKey - 1) + "\n", valid: false),
    EdgeCase("padded key at the minimum", key: "  " + String(repeating: "k", count: minKey) + "\n", valid: true),
    EdgeCase("internal space counts", key: String(repeating: "k", count: minKey - 2) + " k", valid: true),
    EdgeCase("internal space one short", key: String(repeating: "k", count: minKey - 3) + " k", valid: false),
    EdgeCase("graphemes at the minimum", key: String(repeating: family, count: minKey), valid: true),
    EdgeCase("graphemes one short", key: String(repeating: family, count: minKey - 1), valid: false),
]

@Suite("apps setup form") @MainActor struct AppsSetupFormTests {
    // MARK: validation reuses AppsModel.configure's rules

    @Test func endpointRulesAreTheModels() {
        #expect(AppsSetupRules.endpointIssue("") == .endpointEmpty)
        #expect(AppsSetupRules.endpointIssue("   ") == .endpointEmpty)
        #expect(AppsSetupRules.endpointIssue("http://x.vercel.app") == .endpointInvalid, "https only")
        #expect(AppsSetupRules.endpointIssue("https://x.vercel.app/api") == .endpointInvalid, "no path")
        #expect(AppsSetupRules.endpointIssue("https://u:p@x.vercel.app") == .endpointInvalid, "no credentials")
        #expect(AppsSetupRules.endpointIssue("https://x.vercel.app?a=1") == .endpointInvalid, "no query")
        #expect(AppsSetupRules.endpointIssue("companion-apps") == .endpointInvalid, "no host")
        #expect(AppsSetupRules.endpointIssue(goodEndpoint) == nil)
        #expect(AppsSetupRules.endpointIssue(goodEndpoint + "/") == nil, "a trailing slash is trimmed")
    }

    @Test func keyRulesAreTheModels() {
        #expect(AppsSetupRules.keyIssue("") == .keyEmpty)
        #expect(AppsSetupRules.keyIssue("  \n") == .keyEmpty)
        #expect(AppsSetupRules.keyIssue(String(repeating: "k", count: AppsModel.minimumKeyLength - 1)) == .keyShort)
        #expect(AppsSetupRules.keyIssue(String(repeating: "k", count: AppsModel.minimumKeyLength)) == nil)
        #expect(AppsSetupRules.keyIssue(" " + goodKey + " ") == nil, "trimmed, as configure trims it")
    }

    /// One table, both judges: a value the form calls valid must also be one
    /// configure() saves, and the other way round. Rows marked "pinned" record
    /// what Foundation's URL parser does today rather than a choice of ours.
    @Test func theTableUsesTheModelsMinimum() {
        #expect(minKey == AppsModel.minimumKeyLength)
    }

    @Test(arguments: edgeCases) func rulesAndConfigureAgree(_ row: EdgeCase) async {
        let apps = AppsModel(
            secrets: TestSecretStore(), hostSecrets: TestHostSecretStore(),
            defaults: UserDefaults(suiteName: "apps-setup-rules-\(UUID().uuidString)")!,
            makeService: { _, _ in NeverApps() })
        let rulesSay = AppsSetupRules.endpointIssue(row.endpoint) == nil && AppsSetupRules.keyIssue(row.key) == nil
        #expect(rulesSay == row.valid, "rules")
        #expect((await apps.configure(endpoint: row.endpoint, key: row.key) == .saved) == row.valid, "configure")
    }

    @Test func aSaveThatNeverStartedUnlocksTheForm() {
        var flow = AppsSetupFlow()
        let started = flow.submit(endpoint: goodEndpoint, key: goodKey)
        #expect(started)
        #expect(flow.isReadOnly)
        flow.finish(.notStarted)
        #expect(flow.phase == .editing)
        #expect(!flow.isReadOnly, "another save was being checked; this one can be retried")
    }

    // MARK: when errors show

    @Test func pristineShowsNoErrors() {
        let flow = AppsSetupFlow()
        #expect(flow.endpointError("") == nil, "nothing is wrong before the first submit")
        #expect(flow.keyError("") == nil)
    }

    @Test func aSubmitAttemptShowsEveryError() {
        var flow = AppsSetupFlow()
        let accepted = flow.submit(endpoint: "", key: "short")
        #expect(!accepted)
        #expect(flow.phase == .editing)
        #expect(flow.endpointError("") == .endpointEmpty)
        #expect(flow.keyError("short") == .keyShort)
    }

    @Test func errorsFollowTheTypingAfterTheAttempt() {
        var flow = AppsSetupFlow()
        _ = flow.submit(endpoint: "", key: "")
        #expect(flow.endpointError("https") == .endpointInvalid, "the message rewords as the value changes")
        #expect(flow.endpointError(goodEndpoint) == nil, "and clears once the value is good")
        #expect(flow.keyError(goodKey) == nil)
    }

    // MARK: the phase machine

    @Test func aValidSubmitSaves() {
        var flow = AppsSetupFlow()
        let accepted = flow.submit(endpoint: goodEndpoint, key: goodKey)
        #expect(accepted)
        #expect(flow.phase == .saving)
        #expect(flow.isReadOnly, "the fields cannot change under a save")
    }

    @Test func doubleSubmitIsBlocked() {
        var flow = AppsSetupFlow()
        let first = flow.submit(endpoint: goodEndpoint, key: goodKey)
        #expect(first)
        let second = flow.submit(endpoint: goodEndpoint, key: goodKey)
        #expect(!second, "a second submit while saving does nothing")
        #expect(flow.phase == .saving)
        flow.finish(.saved)
        let third = flow.submit(endpoint: goodEndpoint, key: goodKey)
        #expect(!third, "nor once confirmed")
        #expect(flow.phase == .confirmed)
    }

    @Test func aServerFailureKeepsTheForm() {
        var flow = AppsSetupFlow()
        _ = flow.submit(endpoint: goodEndpoint, key: goodKey)
        flow.finish(.serverFailed(.unauthorized))
        #expect(flow.phase == .failed(.server(.unauthorized)))
        #expect(flow.failure == .server(.unauthorized))
        #expect(!flow.isReadOnly, "the person can fix the key")
        let accepted = flow.submit(endpoint: goodEndpoint, key: goodKey)
        #expect(accepted, "and try again")
        #expect(flow.failure == nil, "a new attempt drops the old failure")
    }

    @Test func aStorageFailureKeepsTheForm() {
        var flow = AppsSetupFlow()
        _ = flow.submit(endpoint: goodEndpoint, key: goodKey)
        flow.finish(.storageFailed)
        #expect(flow.phase == .failed(.storage))
        #expect(!flow.isReadOnly)
    }

    @Test func anInvalidRetryDropsTheOldFailure() {
        var flow = AppsSetupFlow()
        _ = flow.submit(endpoint: goodEndpoint, key: goodKey)
        flow.finish(.serverFailed(.unreachable))
        let accepted = flow.submit(endpoint: "", key: goodKey)
        #expect(!accepted)
        #expect(flow.phase == .editing, "the field error is the news now, not the old server answer")
    }

    @Test func aSuccessConfirms() {
        var flow = AppsSetupFlow()
        _ = flow.submit(endpoint: goodEndpoint, key: goodKey)
        flow.finish(.saved)
        #expect(flow.phase == .confirmed)
        #expect(flow.isReadOnly)
    }

    @Test func aStaleFinishIsIgnored() {
        var flow = AppsSetupFlow()
        flow.finish(.saved)
        #expect(flow.phase == .editing, "nothing was saving")
    }

    @Test func theLoadAnswerDecidesTheOutcome() {
        #expect(AppsSetupFlow.Outcome.after(load: .ready) == .saved)
        #expect(AppsSetupFlow.Outcome.after(load: .loading) == .saved,
                "a search that took the list over still found the function")
        #expect(AppsSetupFlow.Outcome.after(load: .failed(.unauthorized)) == .serverFailed(.unauthorized))
        #expect(AppsSetupFlow.Outcome.after(load: .setup) == .storageFailed,
                "configure said yes but nothing can be read back")
    }

    @Test func anInvalidSubmitWhileBusyStaysPut() {
        var saving = AppsSetupFlow()
        _ = saving.submit(endpoint: goodEndpoint, key: goodKey)
        let duringSave = saving.submit(endpoint: "", key: "")
        #expect(!duringSave)
        #expect(saving.phase == .saving, "an empty field cannot pull a running save back to editing")
        var confirmed = saving
        confirmed.finish(.saved)
        let afterConfirm = confirmed.submit(endpoint: "", key: "")
        #expect(!afterConfirm)
        #expect(confirmed.phase == .confirmed)
    }

    @Test func finishAfterAnEndIsIgnored() {
        var failed = AppsSetupFlow()
        _ = failed.submit(endpoint: goodEndpoint, key: goodKey)
        failed.finish(.serverFailed(.unreachable))
        failed.finish(.saved)
        #expect(failed.phase == .failed(.server(.unreachable)), "a late success does not paint over the failure")
        var confirmed = AppsSetupFlow()
        _ = confirmed.submit(endpoint: goodEndpoint, key: goodKey)
        confirmed.finish(.saved)
        confirmed.finish(.storageFailed)
        #expect(confirmed.phase == .confirmed)
    }

    @Test func aStorageFailureThenARetrySucceeds() {
        var flow = AppsSetupFlow()
        _ = flow.submit(endpoint: goodEndpoint, key: goodKey)
        flow.finish(.storageFailed)
        let retry = flow.submit(endpoint: goodEndpoint, key: goodKey)
        #expect(retry)
        #expect(flow.phase == .saving && flow.failure == nil)
        flow.finish(.saved)
        #expect(flow.phase == .confirmed)
    }

    @Test func theAnnouncedIssueIsTheFirstToFix() {
        var flow = AppsSetupFlow()
        #expect(flow.announcedIssue(endpoint: "", key: "") == nil, "nothing is said before the first submit")
        _ = flow.submit(endpoint: "", key: "")
        #expect(flow.announcedIssue(endpoint: "", key: "") == .endpointEmpty, "the address comes first")
        #expect(flow.announcedIssue(endpoint: goodEndpoint, key: "short") == .keyShort)
        #expect(flow.announcedIssue(endpoint: goodEndpoint, key: goodKey) == nil, "nothing to say when both are good")
    }

    // MARK: reduced motion

    @Test func reducedMotionSwapsWithoutTravelOrBlur() {
        let calm = AppsSetupMotion.resolve(reduceMotion: true)
        #expect(calm.faceTravel == 0 && calm.faceExitTravel == 0)
        #expect(calm.faceBlur == 0)
        #expect(calm.messageRise == 0 && calm.messageBlur == 0)
        #expect(calm.messageAnimation == nil, "error rows mount at full height with an instant fade")
        let full = AppsSetupMotion.resolve(reduceMotion: false)
        #expect(full.faceTravel > 0 && full.faceExitTravel > 0 && full.faceBlur > 0)
        #expect(full.messageRise > 0 && full.messageBlur > 0)
        #expect(full.messageAnimation != nil)
    }

    @Test func eachBranchPicksItsAnimations() {
        let calm = AppsSetupMotion.resolve(reduceMotion: true)
        #expect(calm.faceAnimation == MotionCurve.animation(MotionCurve.linear, MotionTime.fast),
                "Arc's reduced faces: a short fade, nothing else")
        #expect(calm.faceExitAnimation == MotionCurve.animation(MotionCurve.linear, MotionTime.fast))
        let full = AppsSetupMotion.resolve(reduceMotion: false)
        #expect(full.faceAnimation == .springSheet, "Arc's smooth spring carries the travel")
        #expect(full.faceExitAnimation == MotionCurve.animation(MotionCurve.glide, MotionTime.fast),
                "Arc's exit: fast on the standard ease, which is glide")
        #expect(full.messageAnimation == .springSheet, "the row opens its height on the same spring")
    }

    @Test func theKeyLengthInTheCopyIsTheModels() async {
        for language in [AppLanguage.en, .es] {
            await Localized.scoped(to: language) {
                for raw in [Localized.string("apps.setup.key.help"), Localized.string("apps.setup.key.short")] {
                    #expect(raw.contains("%ld"), "\(language): the number comes from the model, not the catalog")
                }
                for line in [AppsSetupCopy.keyHelp, AppsSetupCopy.issue(.keyShort)] {
                    #expect(line.contains("\(AppsModel.minimumKeyLength)"), "\(language): \(line)")
                }
            }
        }
    }

    // MARK: copy

    @Test func copyResolvesInBothLanguages() async {
        func lines() -> [String] {
            [AppsSetupIssue.endpointEmpty, .endpointInvalid, .keyEmpty, .keyShort].map(AppsSetupCopy.issue)
                + [AppsSetupCopy.failure(.storage), AppsSetupCopy.failure(.server(.unauthorized))]
                + AppsSetupCopy.fixed
        }
        let english = await Localized.scoped(to: .en) { lines() }
        let spanish = await Localized.scoped(to: .es) { lines() }
        #expect(english.count == spanish.count)
        for (en, es) in zip(english, spanish) {
            #expect(!en.isEmpty && !es.isEmpty)
            #expect(!en.hasPrefix("apps.") && !es.hasPrefix("apps."), "a raw key never reaches the screen")
            #expect(en != es, "'\(es)' is the same in English")
            #expect(!es.contains("\u{2014}"), "no em dashes in Spanish")
        }
    }
}

private final class NeverApps: AppsService, @unchecked Sendable {
    func catalog(query: String, after: String?) async throws -> CatalogPage { throw AppsFailure.unexpected }
    func accounts() async throws -> [ConnectedAccount] { [] }
    func connectLink(app: String) async throws -> URL { throw AppsFailure.unexpected }
    func tools(app: String) async throws -> [AppAction] { [] }
    func disconnect(account: String) async throws {}
    func call(app: String, tool: String, argumentsJSON: String, approved: Bool) async throws -> AppCallResult {
        throw AppsFailure.unexpected
    }
}
