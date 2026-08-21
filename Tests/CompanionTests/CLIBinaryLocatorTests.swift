import CompanionServices
import Foundation
import Testing

// La app es GUI: no hereda el PATH del shell, así que "which" miente.
// La única verdad es el sistema de archivos, como en el prototipo.

@Test @MainActor func cliBinaryLocatorTests() {
    testLocatorPrefersUserLocalBin()
    testLocatorFallsBackToSystemPaths()
    testLocatorReturnsNilWhenAbsent()
}

@MainActor func testLocatorPrefersUserLocalBin() {
    let locator = CLIBinaryLocator(home: "/Users/k") { path in
        ["/Users/k/.local/bin/claude", "/usr/local/bin/claude"].contains(path)
    }
    expectEq(locator.locate("claude"), "/Users/k/.local/bin/claude",
             "~/.local/bin gana: es donde instala el instalador oficial")
}

@MainActor func testLocatorFallsBackToSystemPaths() {
    let locator = CLIBinaryLocator(home: "/Users/k") { path in
        path == "/opt/homebrew/bin/hermes"
    }
    expectEq(locator.locate("hermes"), "/opt/homebrew/bin/hermes",
             "homebrew es candidato cuando ~/.local/bin no tiene el binario")
}

@MainActor func testLocatorReturnsNilWhenAbsent() {
    let locator = CLIBinaryLocator(home: "/Users/k") { _ in false }
    expectEq(locator.locate("claude"), nil, "sin binario no hay ejecutor")
}
