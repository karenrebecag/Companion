import CompanionTestKit
import Foundation
import Testing

// 16p-3: a multi-line Text (`.fixedSize(horizontal: false`) in the window
// screens must get its line height from a TypeRole, and the role must be the
// one its font names. Written as a scan, like ConformanceTests, so a text
// added later without a role fails here instead of drifting back to
// SwiftUI's default leading.

enum TypeLeadingLint {
    /// Files that own the rule. Everything else either has no multi-line Text
    /// or must be listed in `exempt` with its reason.
    static let covered = ["Apps/AppsPage.swift", "Apps/AppPanel.swift", "Apps/ConnectingSheet.swift", "Window/HomePage.swift", "Window/HomeHero.swift"]

    /// Not brought under the rule yet, on purpose. Path prefixes relative to
    /// Sources/CompanionUI.
    static let exempt: [String: String] = [
        "Island/": "the island reads its own leading from AnswerBlockMetrics (measured 1.45-1.62 per block)",
        "Settings/Settings": "Settings rows have no measured line height of their own; move to roles when touched",
        "Welcome/": "the welcome sheet speaks Geist and has no measured line height of its own",
        "Voice/ApprovalSheet.swift": "the approval panel speaks Geist; its leading was never measured",
        "Feedback/": "the feedback modal speaks Geist like the island; only its frame (480, 32, 28) was measured",
        "Apps/OwnMCPSheet.swift": "form sheet reached through Apps; not measured, follow-up",
        "Chat/ChatErrorSurface.swift": "error banner, not a measured screen",
        "DesignSystem/Controls.swift": "shared control internals, no role of their own",
    ]

    static let fontRole: [String: String] = [
        ".font(.uiBody)": "body",
        ".font(.uiCaption)": "micro",
        ".font(Fonts.sans(TypeSize.heroBody))": "heroBody",
    ]

    /// The modifier chains that start at a `Text(` line.
    static func textChains(in src: String) -> [String] {
        let lines = src.components(separatedBy: "\n")
        func indent(_ l: String) -> Int { l.prefix(while: { $0 == " " }).count }
        var chains: [String] = []
        for (i, line) in lines.enumerated() where line.trimmingCharacters(in: .whitespaces).hasPrefix("Text(") {
            var chain = [line.trimmingCharacters(in: .whitespaces)]
            var j = i + 1
            while j < lines.count,
                  lines[j].trimmingCharacters(in: .whitespaces).isEmpty || indent(lines[j]) > indent(line) {
                chain.append(lines[j].trimmingCharacters(in: .whitespaces))
                j += 1
            }
            chains.append(chain.joined(separator: "\n"))
        }
        return chains
    }

    static func role(in chain: String, modifier: String) -> String? {
        guard let r = chain.range(of: modifier + ".") else { return nil }
        return String(chain[r.upperBound...].prefix(while: { $0.isLetter }))
    }

    static func violations(in src: String, file: String) -> [String] {
        var out: [String] = []
        for chain in textChains(in: src) where chain.contains(".fixedSize(horizontal: false") {
            let head = chain.components(separatedBy: "\n").first ?? ""
            let fontRoles = fontRole.filter { chain.contains($0.key) }.map(\.value)
            if let role = role(in: chain, modifier: ".typeRole(") {
                if let font = fontRoles.first, font != role {
                    out.append("\(file): \(head) — font says \(font), typeRole says \(role)")
                }
            } else if let role = role(in: chain, modifier: ".typeLeading(") {
                guard let font = fontRoles.first else {
                    out.append("\(file): \(head) — typeLeading(.\(role)) beside a font with no known role")
                    continue
                }
                if font != role { out.append("\(file): \(head) — font says \(font), typeLeading says \(role)") }
            } else {
                out.append("\(file): \(head) — multi-line Text without a typeRole")
            }
        }
        return out
    }

    static func isExempt(_ rel: String) -> Bool {
        exempt.keys.contains { rel.hasPrefix($0) }
    }
}

@Test func multiLineTextsCarryTheirRoleTests() throws {
    guard let root = Conformance.repoRoot() else { return }
    let base = root.appendingPathComponent("Sources/CompanionUI")
    let all = Conformance.swiftFiles(in: base).sorted(by: { $0.path < $1.path })
    // Un arbol movido o una ruta cubierta obsoleta desarmaria el lint en silencio.
    expect(!all.isEmpty, "Sources/CompanionUI tiene fuentes que escanear")
    for rel in TypeLeadingLint.covered {
        expect(FileManager.default.fileExists(atPath: base.appendingPathComponent(rel).path),
               "covered: \(rel) existe bajo Sources/CompanionUI")
    }
    for file in all {
        let rel = file.path.replacingOccurrences(of: base.path + "/", with: "")
        let src = try String(contentsOf: file, encoding: .utf8)
        let hasMultiLine = TypeLeadingLint.textChains(in: src).contains { $0.contains(".fixedSize(horizontal: false") }
        if TypeLeadingLint.covered.contains(rel) {
            for v in TypeLeadingLint.violations(in: src, file: rel) { expect(false, v) }
        } else if hasMultiLine {
            expect(TypeLeadingLint.isExempt(rel),
                   "\(rel) tiene Text de varias líneas: cúbrelo con typeRole o añádelo a TypeLeadingLint.exempt con su motivo")
        }
    }
}

@Test func theLintCatchesAMissingOrCrossedRoleTests() {
    let ok = """
        Text("a")
            .typeRole(.body)
            .fixedSize(horizontal: false, vertical: true)
        """
    let missing = """
        Text("a")
            .font(.uiBody)
            .fixedSize(horizontal: false, vertical: true)
        """
    let crossedLeading = """
        Text("a")
            .font(.uiBody)
            .typeLeading(.micro)
            .fixedSize(horizontal: false, vertical: true)
        """
    let unmapped = """
        Text("a")
            .font(.uiLabel)
            .typeLeading(.body)
            .fixedSize(horizontal: false, vertical: true)
        """
    let crossedFont = """
        Text("a")
            .font(.uiCaption)
            .typeRole(.body)
            .fixedSize(horizontal: false, vertical: true)
        """
    let oneLine = """
        Text("a")
            .font(.uiBody)
            .lineLimit(1)
        """
    expectEq(TypeLeadingLint.violations(in: ok, file: "t").count, 0, "lint: typeRole basta")
    expectEq(TypeLeadingLint.violations(in: missing, file: "t").count, 1, "lint: falta el rol")
    expectEq(TypeLeadingLint.violations(in: crossedLeading, file: "t").count, 1, "lint: rol cruzado con typeLeading")
    expectEq(TypeLeadingLint.violations(in: unmapped, file: "t").count, 1, "lint: fuente sin rol conocido")
    expectEq(TypeLeadingLint.violations(in: crossedFont, file: "t").count, 1, "lint: fuente y typeRole cruzados")
    expectEq(TypeLeadingLint.violations(in: oneLine, file: "t").count, 0, "lint: una línea no exige rol")
}
