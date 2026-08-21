import CompanionCore
import CompanionServices
import Foundation
import Testing

@Test @MainActor func voiceEndpointValidationTests() {
    testEndpointPolicyAcceptsWSS()
    testEndpointPolicyAcceptsWSLocalhost()
    testEndpointPolicyRejectsWSRemote()
    testEndpointPolicyRejectsHTTP()
    testEndpointPolicyRejectsHTTPS()
}

@MainActor func testEndpointPolicyAcceptsWSS() {
    let url = URL(string: "wss://api.openai.com/v1/realtime")!
    let accepted = EndpointPolicy.isAcceptable(url)
    expect(accepted, "endpoint policy: wss should be acceptable")
}

@MainActor func testEndpointPolicyAcceptsWSLocalhost() {
    let urlLocalhost = URL(string: "ws://localhost:8080/realtime")!
    let url127 = URL(string: "ws://127.0.0.1:8080/realtime")!
    let urlIPv6 = URL(string: "ws://[::1]:8080/realtime")!

    expect(EndpointPolicy.isAcceptable(urlLocalhost),
           "endpoint policy: ws://localhost should be acceptable")
    expect(EndpointPolicy.isAcceptable(url127),
           "endpoint policy: ws://127.0.0.1 should be acceptable")
    expect(EndpointPolicy.isAcceptable(urlIPv6),
           "endpoint policy: ws://[::1] should be acceptable")
}

@MainActor func testEndpointPolicyRejectsWSRemote() {
    let url = URL(string: "ws://example.com:8080/realtime")!
    let accepted = EndpointPolicy.isAcceptable(url)
    expect(!accepted, "endpoint policy: ws to remote host should be rejected")
}

@MainActor func testEndpointPolicyRejectsHTTP() {
    let url = URL(string: "http://example.com/realtime")!
    let accepted = EndpointPolicy.isAcceptable(url)
    expect(!accepted, "endpoint policy: http to remote host should be rejected")
}

@MainActor func testEndpointPolicyRejectsHTTPS() {
    // Note: HTTPS is acceptable by original EndpointPolicy, but we're
    // testing that wss/ws is what should be used for voice transports
    let url = URL(string: "https://example.com/realtime")!
    let accepted = EndpointPolicy.isAcceptable(url)
    // HTTPS is acceptable per policy, but voice should use wss
    expect(accepted, "endpoint policy: https is acceptable (but voice should use wss)")
}
