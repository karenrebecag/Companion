import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// 16p-1 (security review): what reaches the island and the thread is catalog
// copy, never an error's own text; and a catalog key means one thing.

private struct Secret: Error, CustomStringConvertible, LocalizedError {
    var description: String { "SENTINEL-internal-path-/Users/x" }
    var errorDescription: String? { description }
}

@Test @MainActor func copyLeakTests() async {
    for language in [AppLanguage.en, .es] {
        await Localized.scoped(to: language) {
            testErrorCopyComesFromTheCatalog(language)
            testJobFailedNoticeNeverCarriesTheRawError(language)
        }
    }
    testNoCatalogRepeatsAKey()
    testTheJobFailedKeysDoNotCollide()
}

private func errors() -> [Error] {
    let chat: [ChatError] = [.unauthorized, .forbidden, .rateLimited, .timeout, .unreachable,
                             .httpStatus(503), .empty, .noProvider, .invalidKey]
    let secret: [SecretStoreError] = [.emptyValue, .denied, .notAvailable, .unexpected(-25293)]
    let persistence: [PersistenceError] = [.encoding, .decoding, .io]
    let other: [Error] = [
        Secret(),
        NSError(domain: "SENTINEL", code: 7, userInfo: [NSLocalizedDescriptionKey: "SENTINEL-nserror"])]
    return chat + secret + persistence + other
}

@MainActor private func testErrorCopyComesFromTheCatalog(_ language: AppLanguage) {
    let values = catalogValues(language.rawValue)
    for error in errors() {
        let copy = ChatCopy.error(error)
        expect(!copy.contains("SENTINEL"), "S1 \(language.rawValue): '\(copy)' no interpola el error")
        if case ChatError.httpStatus(let code) = error {
            expectEq(copy, String(format: Localized.string("chat.error.httpStatus"), code),
                     "S1: httpStatus solo suma el código")
        } else {
            expect(values.contains(copy),
                   "S1 \(language.rawValue): '\(copy)' es una cadena del catálogo (\(error))")
        }
    }
}

@MainActor private func testJobFailedNoticeNeverCarriesTheRawError(_ language: AppLanguage) {
    for error in errors() {
        let notice = ChatCopy.jobFailedNotice(error)
        expect(!notice.contains("SENTINEL"), "S3: el aviso no lleva la descripción cruda")
        expect(!notice.contains("httpStatus(") && !notice.contains("unexpected("),
               "S3: ni el nombre del caso de un enum")
        expect(!notice.contains("%@"), "S3: la plantilla no queda sin rellenar")
    }
    expect(ChatCopy.jobFailedNotice(ChatError.timeout).contains(ChatCopy.error(ChatError.timeout)),
           "S3: un caso útil se dice con copy del catálogo")
}

@MainActor func testNoCatalogRepeatsAKey() {
    for language in ["en", "es"] {
        let keys = catalogKeyList(language)
        var seen = Set<String>()
        let repeated = keys.filter { !seen.insert($0).inserted }
        expectEq(repeated, [], "S2: \(language).lproj no repite claves")
    }
}

@MainActor func testTheJobFailedKeysDoNotCollide() {
    expect(!ChatCopy.jobFailed.contains("%@"), "S2: el toast corto no arrastra la plantilla")
}

private func catalogLines(_ language: String) -> [String] {
    guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
          let file = try? String(contentsOfFile: path + "/Localizable.strings", encoding: .utf8)
    else { return [] }
    return file.split(separator: "\n").map(String.init)
}

private func catalogKeyList(_ language: String) -> [String] {
    catalogLines(language).compactMap { line in
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("\"") else { return nil }
        return t.dropFirst().split(separator: "\"", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
    }
}

/// Values as the loader sees them: the string between `= "` and `";`.
private func catalogValues(_ language: String) -> Set<String> {
    var out = Set<String>()
    for line in catalogLines(language) {
        guard let eq = line.range(of: "\" = \""), line.hasSuffix("\";") else { continue }
        out.insert(String(line[eq.upperBound...].dropLast(2)).replacingOccurrences(of: "\\\"", with: "\""))
    }
    return out
}
