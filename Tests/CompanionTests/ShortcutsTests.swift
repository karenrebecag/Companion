import CompanionCore
import CompanionUI
import Foundation
import Testing

@Test @MainActor func shortcutsTests() {
    testShortcutCoding()
    testShortcutConflictDetection()
    testDefaultShortcuts()
    testResolveShortcutMatch()
    testResolveShortcutNoMatch()
    testResolveShortcutTextFieldFocused()
}

@MainActor func testResolveShortcutMatch() {
    let set = ShortcutSet(shortcuts: [
        Shortcut(action: .toggleVoice, keyCode: 49, modifiers: KeyModifiers(command: true, option: true))
    ])
    let action = ShortcutResolver.resolve(keyCode: 49, modifiers: KeyModifiers(command: true, option: true), in: set)
    expectEq(action, .toggleVoice, "resolves matching shortcut")
}

@MainActor func testResolveShortcutNoMatch() {
    let set = ShortcutSet(shortcuts: [
        Shortcut(action: .toggleVoice, keyCode: 49, modifiers: KeyModifiers(command: true, option: true))
    ])
    let action = ShortcutResolver.resolve(keyCode: 50, modifiers: KeyModifiers(command: true), in: set)
    expect(action == nil, "returns nil for non-matching keyCode")
}

@MainActor func testResolveShortcutTextFieldFocused() {
    let set = ShortcutSet(shortcuts: [
        Shortcut(action: .toggleVoice, keyCode: 49, modifiers: KeyModifiers(command: true, option: true))
    ])
    // When a text field is focused, shortcuts should not resolve
    let action = ShortcutResolver.resolve(keyCode: 49, modifiers: KeyModifiers(command: true, option: true), in: set, textFieldFocused: true)
    expect(action == nil, "returns nil when text field is focused")
}

@MainActor func testShortcutCoding() {
    let shortcut = Shortcut(
        action: .toggleVoice,
        keyCode: 49,
        modifiers: KeyModifiers(command: true, option: true)
    )

    let encoded = try! JSONEncoder().encode(shortcut)
    let decoded = try! JSONDecoder().decode(Shortcut.self, from: encoded)

    expectEq(decoded.action, shortcut.action, "action round-trips")
    expectEq(decoded.keyCode, shortcut.keyCode, "keyCode round-trips")
    expectEq(decoded.modifiers, shortcut.modifiers, "modifiers round-trip")
}

@MainActor func testShortcutConflictDetection() {
    let shortcut1 = Shortcut(
        action: .toggleVoice,
        keyCode: 49,
        modifiers: KeyModifiers(command: true)
    )
    let shortcut2 = Shortcut(
        action: .toggleMute,
        keyCode: 49,
        modifiers: KeyModifiers(command: true)
    )

    expect(shortcut1.conflictsWith(shortcut2),
           "same keyCode and modifiers conflict")

    let shortcut3 = Shortcut(
        action: .toggleMute,
        keyCode: 48,
        modifiers: KeyModifiers(command: true)
    )
    expect(!shortcut1.conflictsWith(shortcut3),
           "different keyCode does not conflict")
}

@MainActor func testDefaultShortcuts() {
    let defaults = ShortcutSet.defaults
    expect(!defaults.shortcuts.isEmpty, "defaults not empty")

    let toggleVoice = defaults.shortcuts.first { $0.action == .toggleVoice }
    expect(toggleVoice != nil, "toggle voice shortcut exists")

    // No two shortcuts should have the same key binding
    var seen = Set<String>()
    for shortcut in defaults.shortcuts {
        let key = "\(shortcut.keyCode)_\(shortcut.modifiers)"
        expect(!seen.contains(key), "no duplicate shortcuts: \(shortcut.action)")
        seen.insert(key)
    }
}
