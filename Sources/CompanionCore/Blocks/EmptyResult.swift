import Foundation

/// A search that came back empty, painted so it does not read as a failure
/// or as a silent turn. The copy lives in the UI; this only says which search.
package enum EmptyResult: Sendable, Equatable {
    case places(query: String)
    case folder
}
