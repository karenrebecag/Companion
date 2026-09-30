import CompanionCore
import Foundation

/// Writes an exported PNG where she chose (16m-5b). The log names the class
/// of the error, never the path: a save panel's path holds her username and
/// often the name of what she was working on.
package enum DiagramFileWriter {
    package static func write(_ data: Data, to url: URL) -> DiagramSaveResult {
        do {
            try data.write(to: url, options: .atomic)
            return .saved
        } catch {
            let code = (error as NSError)
            Log.app("diagram: the PNG could not be saved (\(code.domain) \(code.code))")
            return .failed
        }
    }
}
