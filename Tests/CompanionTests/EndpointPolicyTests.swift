import CompanionServices
import CompanionCore
import Foundation
import Testing

@Test @MainActor func endpointPolicyTests() {
    testEndpointPolicyHttpsAlwaysAllowed()
    testEndpointPolicyHttpLocalhostAllowed()
    testEndpointPolicyHttp127001Allowed()
    testEndpointPolicyHttpIpv6LocalhostAllowed()
    testEndpointPolicyHttpRemoteHostRejected()
    testEndpointPolicyHttpExampleDotComRejected()
}

@MainActor func testEndpointPolicyHttpsAlwaysAllowed() {
    let url = URL(string: "https://api.openai.com/v1/chat/completions")!
    let allowed = EndpointPolicy.isAcceptable(url)
    expect(allowed, "endpoint: https to any host allowed")
}

@MainActor func testEndpointPolicyHttpLocalhostAllowed() {
    let url = URL(string: "http://localhost:11434/v1/chat/completions")!
    let allowed = EndpointPolicy.isAcceptable(url)
    expect(allowed, "endpoint: http localhost allowed")
}

@MainActor func testEndpointPolicyHttp127001Allowed() {
    let url = URL(string: "http://127.0.0.1:11434/v1")!
    let allowed = EndpointPolicy.isAcceptable(url)
    expect(allowed, "endpoint: http 127.0.0.1 allowed")
}

@MainActor func testEndpointPolicyHttpIpv6LocalhostAllowed() {
    let url = URL(string: "http://[::1]:11434/v1")!
    let allowed = EndpointPolicy.isAcceptable(url)
    expect(allowed, "endpoint: http ::1 (ipv6 localhost) allowed")
}

@MainActor func testEndpointPolicyHttpRemoteHostRejected() {
    let url = URL(string: "http://192.168.1.100:11434/v1")!
    let allowed = EndpointPolicy.isAcceptable(url)
    expect(!allowed, "endpoint: http to remote host rejected")
}

@MainActor func testEndpointPolicyHttpExampleDotComRejected() {
    let url = URL(string: "http://example.com/api")!
    let allowed = EndpointPolicy.isAcceptable(url)
    expect(!allowed, "endpoint: http to non-local domain rejected")
}
