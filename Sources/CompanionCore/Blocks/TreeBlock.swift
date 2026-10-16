import Foundation

// A folder listing as a tree, built from the same walk that answers the model.
// The text the model reads and the tree the user sees come from one traversal,
// so the two cannot disagree about what was there.

package struct TreeBlock: Sendable, Equatable {
    package struct Node: Sendable, Equatable {
        package var name: String
        package var isFolder: Bool
        /// Only folders the walk descended into have children; a folder past
        /// the depth limit stays collapsed with none.
        package var children: [Node]

        package init(name: String, isFolder: Bool, children: [Node] = []) {
            self.name = name
            self.isFolder = isFolder
            self.children = children
        }
    }

    /// Past this the listing is a dump, and the model can ask for a subfolder.
    package static let maxEntries = 250

    package var title: String
    package var nodes: [Node]
    /// Entries seen in every folder the walk read, shown or not.
    package var total: Int

    package init(title: String, nodes: [Node], total: Int) {
        self.title = title
        self.nodes = nodes
        self.total = total
    }

    package var shown: Int { Self.count(nodes) }

    /// Never a silent cap: a truncated listing that does not say so reads as
    /// "this is everything", which is a lie about the folder.
    package var truncated: Bool { total > shown }

    /// The indented text the model reads: a folder ends with "/".
    package var text: [String] {
        Self.lines(nodes, depth: 0)
    }

    private static func count(_ nodes: [Node]) -> Int {
        nodes.reduce(0) { $0 + 1 + count($1.children) }
    }

    private static func lines(_ nodes: [Node], depth: Int) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        return nodes.flatMap { node -> [String] in
            [indent + node.name + (node.isFolder ? "/" : "")] + lines(node.children, depth: depth + 1)
        }
    }
}
