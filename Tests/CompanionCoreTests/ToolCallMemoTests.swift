import CompanionCore
import CompanionTestKit
import Testing

// QA 606: two identical find_places calls in one round drew two identical map
// cards. The repeat is answered from the first call, but only for reads: a
// click between two identical reads changes what the second read sees.
@Test func identicalReadsInOneRoundRunOnce() {
    var memo = ToolCallMemo()
    let args = #"{"query":"cafetería","near":"Roma Norte"}"#
    expectEq(memo.step(name: "find_places", arguments: args, index: 0), .run, "primera lectura corre")
    expectEq(memo.step(name: "find_places", arguments: args, index: 1), .reuse(0),
             "la misma lectura reutiliza la primera respuesta")
}

@Test func aChangeBetweenReadsClearsTheMemo() {
    var memo = ToolCallMemo()
    let args = "{}"
    _ = memo.step(name: "look", arguments: args, index: 0)
    expectEq(memo.step(name: "click", arguments: args, index: 1), .run, "un clic corre")
    expectEq(memo.step(name: "look", arguments: args, index: 2), .run,
             "tras un clic, la lectura mira la pantalla nueva")
}

@Test func repeatedChangesAreNeverReused() {
    var memo = ToolCallMemo()
    expectEq(memo.step(name: "type_text", arguments: "{}", index: 0), .run, "escribir corre")
    expectEq(memo.step(name: "type_text", arguments: "{}", index: 1), .run,
             "escribir dos veces no se fusiona")
}
