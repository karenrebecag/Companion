import Foundation

/// A fetched page is read up to a cap: the model can take only a little of it,
/// and a download that never ends would hold the turn open and the memory with it.
package enum WebFetchBody {
    package static let maxBytes = 2_000_000

    package static func collect<S: AsyncSequence>(_ bytes: S) async throws -> Data where S.Element == UInt8 {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= maxBytes { break }
        }
        return data
    }
}
