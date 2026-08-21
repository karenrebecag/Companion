import CompanionServices
import Foundation
import Testing

@Test @MainActor func redirectPolicyTests() {
    testRedirectPolicySameHostAllowed()
    testRedirectPolicyCrossHostRejected()
    testRedirectPolicyHttpsToHttpRejected()
    testRedirectPolicyDifferentPortRejected()
    testRedirectPolicySameHostDifferentSchemeRejected()
}

@MainActor func testRedirectPolicySameHostAllowed() {
    let from = URL(string: "https://api.openai.com/v1/chat/completions")!
    let to = URL(string: "https://api.openai.com/v1/other")!
    let allowed = RedirectPolicy.allows(from: from, to: to)
    expect(allowed, "redirect: same host + same scheme allowed")
}

@MainActor func testRedirectPolicyCrossHostRejected() {
    let from = URL(string: "https://api.openai.com/v1/chat/completions")!
    let to = URL(string: "https://evil.com/steal")!
    let allowed = RedirectPolicy.allows(from: from, to: to)
    expect(!allowed, "redirect: cross-host redirect rejected")
}

@MainActor func testRedirectPolicyHttpsToHttpRejected() {
    let from = URL(string: "https://api.openai.com/v1/chat/completions")!
    let to = URL(string: "http://api.openai.com/v1/other")!
    let allowed = RedirectPolicy.allows(from: from, to: to)
    expect(!allowed, "redirect: https to http downgrade rejected")
}

@MainActor func testRedirectPolicyDifferentPortRejected() {
    let from = URL(string: "https://api.openai.com:443/v1/chat/completions")!
    let to = URL(string: "https://api.openai.com:8443/v1/other")!
    let allowed = RedirectPolicy.allows(from: from, to: to)
    expect(!allowed, "redirect: different port rejected")
}

@MainActor func testRedirectPolicySameHostDifferentSchemeRejected() {
    let from = URL(string: "https://localhost:11434/v1")!
    let to = URL(string: "http://localhost:11434/v1/other")!
    let allowed = RedirectPolicy.allows(from: from, to: to)
    expect(!allowed, "redirect: same host but different scheme rejected")
}
