import CompanionCore
import Foundation

/// The walk behind list_directory: one traversal feeds both the text the model
/// reads and the tree the card paints.
package enum DirectoryTree {
    private struct Budget {
        var shown = 0
        var total = 0
    }

    package static func build(_ dir: String, title: String, depth: Int) -> TreeBlock {
        var budget = Budget()
        let nodes = walk(dir, depth: depth, budget: &budget)
        return TreeBlock(title: title, nodes: nodes, total: budget.total)
    }

    private static func walk(_ dir: String, depth: Int, budget: inout Budget) -> [TreeBlock.Node] {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: dir)
        } catch {
            return [TreeBlock.Node(name: "(unreadable folder)", isFolder: false)]
        }
        // Dotfiles are noise for the question this tool answers, and a home
        // folder has hundreds of them.
        let visible = names.filter { !$0.hasPrefix(".") }.sorted()
        budget.total += visible.count
        var nodes: [TreeBlock.Node] = []
        for name in visible {
            guard budget.shown < TreeBlock.maxEntries else { break }
            budget.shown += 1
            let full = (dir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: full, isDirectory: &isDir)
            let children = isDir.boolValue && depth > 1
                ? walk(full, depth: depth - 1, budget: &budget)
                : []
            nodes.append(TreeBlock.Node(name: name, isFolder: isDir.boolValue, children: children))
        }
        return nodes
    }
}
