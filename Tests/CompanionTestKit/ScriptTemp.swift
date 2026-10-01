import Foundation
import Testing

package func scriptTempRoot(_ tag: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("scripts21c-\(tag)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

package func removeScriptTemp(_ url: URL, sourceLocation: SourceLocation = #_sourceLocation) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("21c: no se pudo borrar \(url.path): \(error)", sourceLocation: sourceLocation)
    }
}
