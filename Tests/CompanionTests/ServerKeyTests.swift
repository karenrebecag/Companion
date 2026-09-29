import CompanionCore
import Testing

/// What tells one MCP server from another in the Keychain. One property each.

@Test func serverKeyKeepsThePortSoTwoPortsAreTwoServers() {
    expectEq(SecretHost.serverKey(of: "https://h:8443/x"), "h:8443/x", "the port is part of the key")
    expect(SecretHost.serverKey(of: "https://h:8443/x") != SecretHost.serverKey(of: "https://h/x"),
           "another port does not share the token")
}

@Test func serverKeyLeavesTheQueryOut() {
    expectEq(SecretHost.serverKey(of: "https://h/x?a=1"), SecretHost.serverKey(of: "https://h/x?a=2"),
             "the query can carry credentials and is not part of the name")
    expectEq(SecretHost.serverKey(of: "https://h/x?token=secret"), "h/x", "and never appears in it")
}

@Test func serverKeyIgnoresTrailingAndLeadingSlashes() {
    expectEq(SecretHost.serverKey(of: "https://h/x/"), "h/x", "trailing slash")
    expectEq(SecretHost.serverKey(of: "https://h"), "h/", "no path still holds a slash")
    expectEq(SecretHost.serverKey(of: "https://h/"), "h/", "root path is the same")
}

@Test func serverKeyEncodesAnAtSignSoItCannotBreakTheStoredName() {
    expectEq(SecretHost.serverKey(of: "https://h/a@b"), "h/a%40b", "@ in the path is encoded")
}

@Test func serverKeyIsLowercasedAndTrimmed() {
    expectEq(SecretHost.serverKey(of: "  https://H.DEV/Docs  "), "h.dev/docs", "host and path share the Keychain casing")
}

/// Review D6 (code MEDIUM): a bearer token must never go out in the clear,
/// so a URL that is not https has no key and therefore no token.
@Test func serverKeyExistsOnlyForHttps() {
    expectEq(SecretHost.serverKey(of: "http://h/p"), nil, "http has no key: no token rides it")
    expectEq(SecretHost.serverKey(of: "ftp://h/p"), nil, "another scheme has none either")
    expectEq(SecretHost.serverKey(of: "//h/p"), nil, "no scheme has none")
    expectEq(SecretHost.serverKey(of: "HTTPS://h/p"), "h/p", "https in any case works")
}

@Test func serverKeyRejectsAnUnusableHost() {
    expectEq(SecretHost.serverKey(of: "not a url"), nil, "not a url")
    expectEq(SecretHost.serverKey(of: ""), nil, "empty")
}

/// Review D6 (security HIGH): a URL that Foundation and a WHATWG parser read
/// as two different hosts must have no key, or a token stored for one host
/// could ride a request the fetcher sends to the other.

@Test func serverKeyRejectsABackslashHostConfusion() {
    expectEq(SecretHost.serverKey(of: "https://evil.com\\@good.com/"), nil, "Foundation says good.com, WHATWG says evil.com")
}

@Test func serverKeyRejectsABackslashAnywhere() {
    expectEq(SecretHost.serverKey(of: "https://h.com/a\\b"), nil, "in the path")
    expectEq(SecretHost.serverKey(of: "https://h.com/?q=\\"), nil, "in the query")
    expectEq(SecretHost.serverKey(of: "https://h.com\\"), nil, "right after the host")
}

@Test func serverKeyRejectsAnEncodedSlashInTheHostSoItCannotCollide() {
    expectEq(SecretHost.serverKey(of: "https://a%2Fb/p"), nil, "the decoded host would read a/b")
    expectEq(SecretHost.serverKey(of: "https://a/b/p"), "a/b/p", "the honest server keeps its key")
    expect(SecretHost.serverKey(of: "https://a%2Fb/p") != SecretHost.serverKey(of: "https://a/b/p"),
           "no shared token")
}

@Test func serverKeyRejectsUserinfo() {
    expectEq(SecretHost.serverKey(of: "https://u:p@a.com/p"), nil, "user and password")
    expectEq(SecretHost.serverKey(of: "https://u@a.com/p"), nil, "user only")
}

@Test func serverKeyRejectsAPercentEncodedHost() {
    expectEq(SecretHost.serverKey(of: "https://a%2Eb.com/p"), nil, "a decoded dot is still a differential")
    expectEq(SecretHost.serverKey(of: "https://a%40b.com/p"), nil, "encoded at sign")
}

@Test func serverKeyKeepsTheCleanCasesItAlreadyResolved() {
    expectEq(SecretHost.serverKey(of: "hTTps://a.com/p"), "a.com/p", "scheme case")
    for bad in ["//a.com/p", "a.com/p", "https:a.com/p", "https:///a.com/p", "https://a b/p"] {
        expectEq(SecretHost.serverKey(of: bad), nil, "\(bad) has no key")
    }
}
