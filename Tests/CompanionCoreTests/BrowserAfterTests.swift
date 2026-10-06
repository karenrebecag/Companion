import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// What an action did to the page travels as a structured `after`, never as page text: the host decodes
// flags and counts and writes the sentence itself, in the user's language.

private func after(_ json: String, done: String = "clicked") -> BrowserAfter? {
    let line = #"{"id":9,"result":{"done":"\#(done)","after":\#(json)}}"#
    if case .success(.acted(_, _, let after)) = BrowserCodec.decode(line: line) { return after }
    return nil
}

@Test func codecDecodesAnAfterNextToTheDoneNote() {
    let line = #"{"id":9,"result":{"done":"clicked","after":{"navigated":false,"urlChanged":true,"opened":"menu","changed":true,"fieldChars":null}}}"#
    expectEq(BrowserCodec.decode(line: line),
             .success(.acted(id: 9, message: "clicked", after: BrowserAfter(
                 navigated: false, urlChanged: true, opened: .menu, changed: true, fieldChars: nil))),
             "done and after both survive")
}

@Test func codecKeepsAPlainDoneWhenThereIsNoAfter() {
    expectEq(BrowserCodec.decode(line: #"{"id":9,"result":{"done":"clicked"}}"#),
             .success(.done(id: 9, message: "clicked")), "absent after: the old shape")
    expectEq(BrowserCodec.decode(line: #"{"id":9,"result":{"done":"clicked","after":null}}"#),
             .success(.done(id: 9, message: "clicked")), "null after: the old shape")
    expectEq(BrowserCodec.decode(line: #"{"id":9,"result":{"done":"clicked","after":"nonsense"}}"#),
             .success(.done(id: 9, message: "clicked")), "malformed after is dropped, not trusted")
}

@Test func codecAcceptsOnlyTheKnownOverlaysAndABoundedFieldLength() {
    expectEq(after(#"{"opened":"<script>"}"#)?.opened, nil, "an unknown opened kind is dropped")
    expectEq(after(#"{"opened":"dialog"}"#)?.opened, .dialog, "dialog")
    expectEq(after(#"{"opened":"listbox"}"#)?.opened, .listbox, "listbox")
    expectEq(after(#"{"fieldChars":12}"#)?.fieldChars, 12, "a count")
    expectEq(after(#"{"fieldChars":-3}"#)?.fieldChars, nil, "negative is dropped")
    expectEq(after(#"{"fieldChars":"hunter2"}"#)?.fieldChars, nil, "a string is never a count")
    expectEq(after(#"{"fieldChars":99999999999}"#)?.fieldChars, nil, "absurd lengths are dropped")
    expectEq(after(#"{"changed":"yes"}"#)?.changed, false, "a non-boolean is false")
}

@Test func theExactMatchNotesStillDecodeWithAnAfterAttached() {
    let line = #"{"id":9,"result":{"done":"typed without line breaks","after":{"changed":true,"fieldChars":5}}}"#
    guard case .success(let reply) = BrowserCodec.decode(line: line) else { Issue.record("no decode"); return }
    expectEq(reply.doneMessage, BrowserCopy.typedWithoutLineBreaks, "the note is still readable by exact match")
    expectEq(reply.after?.fieldChars, 5, "and the after rides along")
    expectEq(BrowserInbound.done(id: 1, message: "still loading").doneMessage, BrowserCopy.stillLoading, "plain done")
    expectEq(BrowserInbound.done(id: 1, message: "x").after, nil, "plain done has none")
}

// MARK: - rendering

private let quiet = BrowserAfter(navigated: false, urlChanged: false, opened: nil, changed: false, fieldChars: nil)

@Test func afterNoteSaysWhatChangedInBothLanguages() {
    let cases: [(BrowserAfter, en: String, es: String)] = [
        (quiet, "nothing on the page changed", "nada en la página cambió"),
        (BrowserAfter(navigated: false, urlChanged: false, opened: nil, changed: true, fieldChars: nil),
         "the page changed", "la página cambió"),
        (BrowserAfter(navigated: false, urlChanged: true, opened: nil, changed: true, fieldChars: nil),
         "the address changed", "la dirección cambió"),
        (BrowserAfter(navigated: true, urlChanged: true, opened: nil, changed: true, fieldChars: nil),
         "the page navigated", "la página navegó"),
        (BrowserAfter(navigated: false, urlChanged: false, opened: .dialog, changed: true, fieldChars: nil),
         "a dialog opened", "se abrió un diálogo"),
        (BrowserAfter(navigated: false, urlChanged: false, opened: .menu, changed: true, fieldChars: nil),
         "a menu opened", "se abrió un menú"),
        (BrowserAfter(navigated: false, urlChanged: false, opened: .listbox, changed: true, fieldChars: nil),
         "a list of options opened", "se abrió una lista de opciones"),
        (BrowserAfter(navigated: false, urlChanged: false, opened: nil, changed: false, fieldChars: 7),
         "the field now holds 7 characters", "el campo ahora tiene 7 caracteres"),
    ]
    for (value, en, es) in cases {
        expect(BrowserCopy.afterNote(value, .en).localizedCaseInsensitiveContains(en), "en: \(en)")
        expect(BrowserCopy.afterNote(value, .es).localizedCaseInsensitiveContains(es), "es: \(es)")
    }
}

@Test func aTypedFieldNeverClaimsNothingChanged() {
    let typed = BrowserAfter(navigated: false, urlChanged: false, opened: nil, changed: false, fieldChars: 3)
    expect(!BrowserCopy.afterNote(typed, .en).localizedCaseInsensitiveContains("nothing"), "typing changed the field")
}

@Test func theNoteHoldsOnlyFixedWordingAndNumbers() {
    let note = BrowserCopy.afterNote(
        BrowserAfter(navigated: false, urlChanged: true, opened: .menu, changed: true, fieldChars: 4), .en)
    expect(note.count < 160, "one short line: \(note)")
    expect(!note.contains("\n"), "single line")
}
