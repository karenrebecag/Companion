import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// The AX read the verifier and the control chooser share. The fake tree
// stands in for Accessibility: an element is an index, so each test names the
// tree it reads. Clocks are injected; nothing here asserts wall-clock time.

private struct FakeElement {
    var kind: ScreenKind
    var details = ScreenDetails()
    var children: [Int] = []
}

private final class FakeTree: ScreenTree {
    typealias Element = Int
    var elements: [FakeElement] = []
    /// Elements whose value the walk asked for.
    var valueReads: [Int] = []

    func add(_ element: FakeElement) -> Int {
        elements.append(element)
        return elements.count - 1
    }

    func attach(_ child: Int, to parent: Int) {
        elements[parent].children.append(child)
    }

    func kind(of element: Int) -> ScreenKind { elements[element].kind }

    func details(of element: Int, readValue: Bool) -> ScreenDetails {
        var details = elements[element].details
        if readValue { valueReads.append(element) } else { details.value = "" }
        return details
    }

    func value(of element: Int) -> String { elements[element].details.value }

    func children(of element: Int) -> [Int] { elements[element].children }
}

/// A clock that advances a fixed step on every read: a budget cut is then a
/// count of reads, never of seconds.
private final class SteppedClock {
    let step: Duration
    private var now: Duration = .zero

    init(step: Duration) { self.step = step }

    func elapsed() -> Duration {
        now += step
        return now
    }
}

private func plain(_ role: String, title: String = "", value: String = "") -> FakeElement {
    FakeElement(kind: ScreenKind(role: role, subrole: "", secure: false),
                details: ScreenDetails(title: title, value: value))
}

private func walk(_ tree: FakeTree, root: Int, budget: ReadBudget, step: Duration = .milliseconds(1))
    -> ScreenReadResult<Int>
{
    let clock = SteppedClock(step: step)
    return ScreenWalker(tree: tree, budget: budget, elapsed: { clock.elapsed() })
        .walk(roots: [root])
}

// A notes window whose note list (300 rows, each row > cell > text) comes
// before its toolbar in the same split group. Rows sit four levels down, the
// toolbar's button three: breadth-first reads the button before the list's
// rows run the budget out. Depth-first read the list first and lost it.
@Test func theToolbarIsReadBeforeAHugeListInTheSameGroup() {
    let tree = FakeTree()
    let window = tree.add(plain("AXWindow"))
    let split = tree.add(plain("AXSplitGroup"))
    tree.attach(split, to: window)
    let list = tree.add(plain("AXScrollArea"))
    let outline = tree.add(plain("AXOutline"))
    let toolbar = tree.add(plain("AXToolbar"))
    tree.attach(list, to: split)
    tree.attach(outline, to: list)
    tree.attach(toolbar, to: split)
    for index in 0..<300 {
        let row = tree.add(plain("AXRow"))
        let cell = tree.add(plain("AXCell"))
        let text = tree.add(plain("AXStaticText", value: "nota \(index)"))
        tree.attach(row, to: outline)
        tree.attach(cell, to: row)
        tree.attach(text, to: cell)
    }
    let button = tree.add(plain("AXButton", title: "Nueva nota"))
    tree.attach(button, to: toolbar)

    let result = walk(tree, root: window, budget: ReadBudget(time: .seconds(60), nodes: 20))

    expect(result.nodes.contains { $0.label == "Nueva nota" }, "la barra se lee antes que la lista")
    expect(result.partial, "la lista no cabe en el presupuesto: se dice parcial")
}

@Test func theNodeBudgetCutsTheWalkAndOnlyAnUnreadTreeIsPartial() {
    let tree = FakeTree()
    let window = tree.add(plain("AXWindow"))
    for index in 0..<50 {
        tree.attach(tree.add(plain("AXStaticText", value: "fila \(index)")), to: window)
    }
    let cut = walk(tree, root: window, budget: ReadBudget(time: .seconds(60), nodes: 10))
    expectEq(cut.nodes.count, 9, "diez elementos visitados: la ventana y nueve filas")
    expect(cut.partial, "con filas sin leer el resultado es parcial")

    let small = FakeTree()
    let smallWindow = small.add(plain("AXWindow"))
    small.attach(small.add(plain("AXStaticText", value: "uno")), to: smallWindow)
    let whole = walk(small, root: smallWindow, budget: ReadBudget(time: .seconds(60), nodes: 10))
    expect(!whole.partial, "todo cabe: no es parcial")
}

@Test func theTimeBudgetCutsOnTheInjectedClock() {
    let tree = FakeTree()
    let window = tree.add(plain("AXWindow"))
    for index in 0..<20 {
        tree.attach(tree.add(plain("AXStaticText", value: "fila \(index)")), to: window)
    }
    let result = walk(tree, root: window, budget: ReadBudget(time: .milliseconds(5), nodes: 900))
    expect(result.partial, "el reloj inyectado agota los 5 ms antes de las 21 visitas")
    expect(result.nodes.count < 21, "la cuenta se corta por tiempo, no por nodos")
}

@Test func aSecureFieldIsLabelOnlyAndItsValueIsNeverRead() {
    let tree = FakeTree()
    let window = tree.add(plain("AXWindow"))
    let password = tree.add(FakeElement(
        kind: ScreenKind(role: "AXTextField", subrole: "AXSecureTextField", secure: true),
        details: ScreenDetails(title: "Contraseña", value: "hunter2"),
        children: []))
    let glyph = tree.add(plain("AXStaticText", value: "h"))
    tree.attach(password, to: window)
    tree.attach(glyph, to: password)

    let result = walk(tree, root: window, budget: ReadBudget.standard)
    let snapshot = ScreenSnapshot(walk: ScreenWalk(
        nodes: result.nodes, partial: result.partial, window: "Notas", generation: 1))

    expect(!tree.valueReads.contains(password), "el valor del campo seguro nunca se pide al árbol")
    expect(!tree.valueReads.contains(glyph), "los hijos de un campo seguro no se leen")
    let field = snapshot.elements.first { $0.secure }
    expectEq(field?.label, "Contraseña", "label del campo seguro")
    expect(field?.value == nil, "sin valor en el snapshot")

    let leaked = ScanNode(role: "AXTextField", subrole: "AXSecureTextField", label: "Clave",
                          value: "hunter2", secure: true)
    let handed = ScreenSnapshot(walk: ScreenWalk(nodes: [leaked], partial: false, window: "x", generation: 1))
    expect(handed.elements.first?.value == nil, "aunque el adaptador entregue el valor, no sale del snapshot")
}

@Test func aSnapshotNumbersItsElementsInWalkOrder() {
    let snapshot = ScreenSnapshot(walk: ScreenWalk(
        nodes: [
            ScanNode(role: "AXButton", subrole: "", label: "Guardar", value: nil, secure: false),
            ScanNode(role: "AXStaticText", subrole: "", label: "", value: "Hola", secure: false),
        ],
        partial: false, window: "Notas", generation: 1))
    expectEq(snapshot.elements.map(\.id), [1, 2], "ids 1..n en el orden del recorrido")
    expectEq(snapshot.elements.last?.label, "Hola", "un texto lleva sus palabras como label")
}

private func snapshot(_ elements: [SnapshotElement], partial: Bool = false) -> ScreenSnapshot {
    ScreenSnapshot(window: "Notas", elements: elements, partial: partial)
}

private func element(
    _ id: Int, _ role: String, _ label: String, value: String? = nil, enabled: Bool = true
) -> SnapshotElement {
    SnapshotElement(id: id, role: role, label: label, value: value, secure: false, enabled: enabled, focused: false)
}

@Test func aDiffReportsWhatAppearedDisappearedAndChanged() {
    let before = snapshot([
        element(1, "AXButton", "Guardar"),
        element(2, "AXTextField", "Título", value: "a"),
        element(3, "AXStaticText", "Nota 1"),
    ])
    let after = snapshot([
        element(1, "AXButton", "Guardar", enabled: false),
        element(2, "AXTextField", "Título", value: "b"),
        element(3, "AXStaticText", "Nota 2"),
    ])
    let diff = ScreenDiff(before: before, after: after)

    expectEq(diff.appeared.map(\.label), ["Nota 2"], "aparece")
    expectEq(diff.disappeared.map(\.label), ["Nota 1"], "desaparece")
    expectEq(diff.changed.map(\.after.label), ["Guardar", "Título"], "cambia: habilitado y valor")
    expect(!diff.partial, "dos lecturas completas no son parciales")
    expect(!diff.isEmpty, "hay cambios")
}

@Test func aPartialReadMarksTheDiffPartial() {
    let before = snapshot([element(1, "AXButton", "Guardar")])
    let after = snapshot([element(1, "AXButton", "Guardar")], partial: true)
    let diff = ScreenDiff(before: before, after: after)
    expect(diff.partial, "una lectura cortada se marca en el diff")
    expect(diff.isEmpty, "sin cambios reales")
}

@Test func rereadStopsAtTheFirstTryWhoseDiffIsNotEmpty() async {
    let before = snapshot([element(1, "AXButton", "Guardar")])
    let unchanged = snapshot([element(1, "AXButton", "Guardar")])
    let changed = snapshot([element(1, "AXButton", "Guardada")])
    let reads = LockedBox([unchanged, changed])
    let pauses = LockedBox<[Duration]>([])

    let reread = ScreenReread(
        read: { reads.withLock { $0.isEmpty ? nil : $0.removeFirst() } },
        pause: { delay in pauses.withLock { $0.append(delay) } })
    let outcome = await reread.reread(after: before)

    expectEq(outcome.tries, 2, "para en el segundo intento, cuando ya hubo diferencia")
    expectEq(pauses.value, [.milliseconds(200), .milliseconds(400)], "espera el backoff hasta ahí")
    expect(outcome.changed, "el resultado dice que cambió")
}

@Test func rereadGivesUpAfterFourTriesOnTheBackoff() async {
    let before = snapshot([element(1, "AXButton", "Guardar")])
    let pauses = LockedBox<[Duration]>([])

    let reread = ScreenReread(
        read: { before },
        pause: { delay in pauses.withLock { $0.append(delay) } })
    let outcome = await reread.reread(after: before)

    expectEq(outcome.tries, 4, "cuatro intentos y ni uno más")
    expectEq(pauses.value,
             [.milliseconds(200), .milliseconds(400), .milliseconds(800), .milliseconds(1500)],
             "0.2, 0.4, 0.8 y 1.5 s")
    expect(!outcome.changed, "nada cambió: se reporta sin diferencia")
}

// MEDIUM-1 (security review of #352): a secure child's text must never become
// its unlabeled parent's caption, and the walk must not descend into it.
@Test func aSecureChildIsSkippedWhenReadingACaption() {
    let tree = FakeTree()
    let window = tree.add(plain("AXWindow"))
    let button = tree.add(plain("AXButton"))
    tree.attach(button, to: window)
    let secure = tree.add(FakeElement(
        kind: ScreenKind(role: "AXTextField", subrole: "AXSecureTextField", secure: true),
        details: ScreenDetails(value: "hunter2"), children: []))
    let glyph = tree.add(plain("AXStaticText", value: "h"))
    let caption = tree.add(plain("AXStaticText", value: "Enviar"))
    tree.attach(secure, to: button)
    tree.attach(glyph, to: secure)
    tree.attach(caption, to: button)

    let result = walk(tree, root: window, budget: ReadBudget.standard)
    let label = result.nodes.first { $0.role == "AXButton" }?.label
    expectEq(label, "Enviar", "el pie es el texto visible, nunca el del campo seguro")
    expect(!result.nodes.contains { $0.label == "hunter2" || $0.value == "hunter2" },
           "el valor del campo seguro no llega a ningún nodo")
}

// MEDIUM-2: a secure element never carries a value, whoever builds it.
@Test func aSnapshotElementNeverCarriesAValueWhenItIsSecure() {
    let element = SnapshotElement(
        id: 1, role: "AXTextField", label: "Clave", value: "hunter2",
        secure: true, enabled: true, focused: false)
    expect(element.value == nil, "un campo seguro no tiene valor aunque lo pasen")
}
