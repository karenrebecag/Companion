import Foundation

extension SyntaxTokenizer {
    enum Family: Equatable {
        case swift, javascript, python, json, shell, markdown, plain

        static func of(_ lang: String) -> Family {
            switch lang.lowercased() {
            case "swift", "swiftui": .swift
            case "js", "javascript", "ts", "typescript", "tsx", "jsx": .javascript
            case "py", "python": .python
            case "json": .json
            case "bash", "sh", "zsh", "shell": .shell
            case "md", "markdown": .markdown
            default: .plain
            }
        }

        var lineComment: String? {
            switch self {
            case .swift, .javascript: "//"
            default: nil
            }
        }

        var blockComment: (String, String)? {
            switch self {
            case .swift, .javascript: ("/*", "*/")
            default: nil
            }
        }

        var hashComment: Bool {
            self == .python || self == .shell
        }

        var singleQuotes: Bool { self != .json && self != .plain }
        var backticks: Bool {
            self == .javascript || self == .shell || self == .markdown
        }
        var tripleQuotes: Bool { self == .python || self == .swift }
        var capitalTypes: Bool { self == .swift || self == .javascript }

        var keywords: Set<String> {
            switch self {
            case .swift:
                [
                    "associatedtype", "actor", "any", "as", "async", "await",
                    "break", "case", "catch", "class", "continue", "default",
                    "defer", "deinit", "do", "else", "enum", "extension",
                    "fallthrough", "false", "fileprivate", "for", "func",
                    "guard", "if", "import", "in", "init", "inout", "internal",
                    "is", "let", "macro", "nil", "nonisolated", "open",
                    "operator", "override", "private", "protocol", "public",
                    "repeat", "return", "rethrows", "self", "Self", "some",
                    "static", "struct", "subscript", "super", "switch",
                    "throw", "throws", "true", "try", "typealias", "var",
                    "where", "while", "convenience", "dynamic", "final",
                    "indirect", "lazy", "mutating", "nonmutating", "optional",
                    "required", "unowned", "weak", "package",
                ]
            case .javascript:
                [
                    "async", "await", "break", "case", "catch", "class",
                    "const", "continue", "debugger", "default", "delete",
                    "do", "else", "export", "extends", "false", "finally",
                    "for", "from", "function", "if", "import", "in",
                    "instanceof", "let", "new", "null", "of", "return",
                    "static", "super", "switch", "this", "throw", "true",
                    "try", "typeof", "undefined", "var", "void", "while",
                    "with", "yield", "enum", "implements", "interface",
                    "package", "private", "protected", "public",
                ]
            case .python:
                [
                    "and", "as", "assert", "async", "await", "break", "class",
                    "continue", "def", "del", "elif", "else", "except",
                    "False", "finally", "for", "from", "global", "if",
                    "import", "in", "is", "lambda", "None", "nonlocal",
                    "not", "or", "pass", "raise", "return", "True", "try",
                    "while", "with", "yield",
                ]
            case .json:
                ["true", "false", "null"]
            case .shell:
                [
                    "if", "then", "else", "elif", "fi", "for", "while", "do",
                    "done", "case", "esac", "in", "function", "return",
                    "export", "local", "readonly", "unset", "shift",
                ]
            case .markdown, .plain:
                []
            }
        }
    }
}
