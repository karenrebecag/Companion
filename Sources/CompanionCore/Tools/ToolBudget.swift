import Foundation

/// A provider rejects a request whose `tools` array is over its cap, so the
/// list is cut here, once, where every provider's request is built.
package enum ToolBudget: Sendable {
    /// Core tools keep their order and come first; connected-app tools fill
    /// what is left, in the order given.
    ///
    /// HACK: apps beyond the cap are simply dropped, in runner order. The
    /// turn-level scoping (one app per turn, `find_app_tools`) keeps this
    /// path rare; upgrade trigger: a single app that alone exceeds the cap,
    /// then rank its tools by the turn's words instead of by position.
    package static func fit(_ tools: [ToolSpec], cap: Int) -> [ToolSpec] {
        guard cap >= 0, tools.count > cap else { return tools }
        let core = tools.filter { !$0.isConnectedApp }
        let apps = tools.filter(\.isConnectedApp)
        return Array((core + apps).prefix(cap))
    }
}
