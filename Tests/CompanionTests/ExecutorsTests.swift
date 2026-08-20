import CompanionCore

@MainActor func executorsTests() {
    testExecutorCatalogNativeAlways()
    testExecutorCatalogDetectsOptional()
    testExecutorCatalogSkipsDuplicateDetected()
    testExecutorIDIdentity()
}

@MainActor func testExecutorCatalogNativeAlways() {
    let listed = ExecutorCatalog.list(detected: [])
    expectEq(listed, [ExecutorCatalog.native],
             "catalog: sin detectados queda solo native")
    expectEq(ExecutorCatalog.native.id, .native, "catalog: native.id es .native")
    expectEq(ExecutorCatalog.native.id.rawValue, "native",
             "catalog: el id crudo es native")
    expectEq(ExecutorCatalog.native.shortName, "native",
             "catalog: shortName native")
    expectEq(ExecutorCatalog.native.title, "Nativo",
             "catalog: título Nativo")
    expect(ExecutorCatalog.native.kind == .native, "catalog: kind native")
    expectEq(ExecutorCatalog.native.modelArgs, [],
             "catalog: native no lleva flags de modelo")
}

@MainActor func testExecutorCatalogDetectsOptional() {
    let claude = ExecutorDescriptor(
        id: ExecutorID(rawValue: "claude"),
        shortName: "claude",
        title: "Claude Code",
        kind: .detectedCLI,
        modelArgs: ["--model", "sonnet"]
    )
    let impostor = ExecutorDescriptor(
        id: .native,
        shortName: "native-dup",
        title: "Impostor",
        kind: .native
    )
    let listed = ExecutorCatalog.list(detected: [impostor, claude])
    expectEq(listed.count, 2, "catalog: id native duplicado no se repite")
    expectEq(listed[0], ExecutorCatalog.native, "catalog: native encabeza")
    expectEq(listed[1], claude, "catalog: claude detectado va después")
    expect(listed[1].kind == .detectedCLI, "catalog: claude es CLI detectado")
    expectEq(listed[1].modelArgs, ["--model", "sonnet"],
             "catalog: modelArgs del CLI viajan")
    let shorts = listed.map(\.shortName)
    expectEq(Set(shorts).count, shorts.count, "catalog: shorts únicos")
}

@MainActor func testExecutorCatalogSkipsDuplicateDetected() {
    let a = ExecutorDescriptor(
        id: ExecutorID(rawValue: "claude"),
        shortName: "claude",
        title: "Claude Code",
        kind: .detectedCLI
    )
    let aDup = ExecutorDescriptor(
        id: ExecutorID(rawValue: "claude"),
        shortName: "claude-dup",
        title: "Otra Claude",
        kind: .detectedCLI
    )
    let b = ExecutorDescriptor(
        id: ExecutorID(rawValue: "hermes"),
        shortName: "hermes",
        title: "Hermes",
        kind: .detectedCLI
    )
    let nene = ExecutorDescriptor(
        id: ExecutorID(rawValue: "ñoño"),
        shortName: "ñoño",
        title: "Ñoño",
        kind: .detectedCLI
    )
    let empty = ExecutorDescriptor(
        id: ExecutorID(rawValue: ""),
        shortName: "",
        title: "",
        kind: .detectedCLI
    )
    let listed = ExecutorCatalog.list(detected: [a, aDup, b, nene, empty])
    expectEq(listed.map(\.id.rawValue), ["native", "claude", "hermes", "ñoño", ""],
             "catalog: orden de detección, ids únicos, unicode y vacío")
    expectEq(listed[0].shortName, "native", "catalog: native no se mueve")
    expectEq(Set(listed.map(\.id)).count, listed.count,
             "catalog: ningún id se repite")
    let bare = ExecutorDescriptor(
        id: ExecutorID(rawValue: "x"),
        shortName: "x",
        title: "X",
        kind: .detectedCLI)
    expectEq(bare.modelArgs, [], "descriptor: modelArgs vacíos por default")
}

@MainActor func testExecutorIDIdentity() {
    expect(ExecutorID.native == ExecutorID(rawValue: "native"),
           "id: native equivale a raw native")
    expect(ExecutorID(rawValue: "claude") != .native,
           "id: otro raw no es native")
    var seen: Set<ExecutorID> = []
    expect(seen.insert(.native).inserted, "id: entra al set")
    expect(!seen.insert(ExecutorID(rawValue: "native")).inserted,
           "id: Hashable colapsa el mismo raw")
    expectEq(ExecutorCatalog.native.id, ExecutorCatalog.native.id,
             "id: Identifiable usa ExecutorID")
}
