import CompanionServices
import CompanionCore
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func endpointPolicyTests() {
    testEndpointPolicyHttpsAlwaysAllowed()
    testEndpointPolicyHttpLocalhostAllowed()
    testEndpointPolicyHttp127001Allowed()
    testEndpointPolicyHttpIpv6LocalhostAllowed()
    testEndpointPolicyHttpRemoteHostRejected()
    testEndpointPolicyHttpExampleDotComRejected()
    testPageFetchRefusesPrivateHosts()
    testPageFetchRedirectToPrivateHostIsCancelled()
}

// CN-004: the page fetch is public https only; EndpointPolicy keeps localhost for Ollama.
@MainActor func testPageFetchRefusesPrivateHosts() {
    expect(PageFetchPolicy.isAcceptable(URL(string: "https://example.com/a")!), "page: host público https ok")
    for raw in ["https://localhost/", "https://127.0.0.1/", "https://10.0.0.5/", "https://192.168.1.1/",
                "https://172.16.0.1/", "https://169.254.169.254/latest", "https://100.64.0.1/",
                "https://[::1]/", "https://[fe80::1]/", "https://[::ffff:127.0.0.1]/",
                "https://router.local/", "https://2130706433/", "http://example.com/"] {
        expect(!PageFetchPolicy.isAcceptable(URL(string: raw)!), "page: \(raw) rechazado")
    }
}

@MainActor func testPageFetchRedirectToPrivateHostIsCancelled() {
    let task = URLSession(configuration: .ephemeral).dataTask(with: URL(string: "https://example.com")!)
    let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 302,
                                   httpVersion: nil, headerFields: nil)!
    func followed(_ target: String) -> Bool {
        var result: URLRequest?
        PageFetchRedirectDelegate().urlSession(
            .shared, task: task, willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: URL(string: target)!)) { result = $0 }
        return result != nil
    }
    expect(!followed("https://169.254.169.254/latest/meta-data"), "redirect a link-local: cancelado")
    expect(followed("https://example.org/next"), "redirect a host público: sigue")
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
