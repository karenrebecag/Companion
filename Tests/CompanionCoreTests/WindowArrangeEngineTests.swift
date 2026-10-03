import CompanionCore
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

// The arrange and undo flow end to end against the fake screen: what moves,
// what is reported, when the snapshot is taken and kept, and what happens
// when the screen refuses or changes under it.

private func screen(trusted: Bool = true) -> FakeWindowArranger {
    FakeWindowArranger(trusted: trusted, displays: [WindowFixtures.laptop, WindowFixtures.external], windows: [
        WindowFixtures.window(1, "Safari", "Apple", frame: WindowRect(x: 100, y: 100, width: 800, height: 600)),
        WindowFixtures.window(2, "Code", "main.swift", frame: WindowRect(x: 200, y: 150, width: 900, height: 700)),
        WindowFixtures.window(3, "Notes", "groceries", frame: WindowRect(x: 300, y: 200, width: 500, height: 400),
                              minimized: true),
    ])
}

private func request(_ layout: String, _ apps: [String], screen: Int = 1, dryRun: Bool = false) -> ArrangeWindowsCall {
    .arrange(ArrangeRequest(layout: layout, apps: apps, screen: screen, dryRun: dryRun))
}

private func failure(_ result: Result<String, ContractError>, _ label: String,
                     sourceLocation: SourceLocation = #_sourceLocation) -> ContractError? {
    guard case .failure(let error) = result else {
        Issue.record("\(label): expected a failure", sourceLocation: sourceLocation)
        return nil
    }
    return error
}

private func glyphFree(_ text: String) -> Bool {
    !text.unicodeScalars.contains {
        $0.properties.isEmojiPresentation || "\u{2713}\u{2714}\u{2717}\u{2718}".unicodeScalars.contains($0)
    }
}

@Test func windowArrangeDryRunPlansWithoutMoving() async throws {
    let fake = screen()
    let undo = ArrangeUndoStore()
    let engine = WindowArrangeEngine(arranging: fake, undo: undo)
    let report = try await engine.run(request("left-right", ["safari", "notes"], dryRun: true)).get()
    expect(report.hasPrefix("Layout 'left-right' on Display 1 (would go):"), "dry run: says would go")
    expect(report.contains("Safari: 756×949 @ 0,33  (now 800×600 @ 100,100 on Display 1, visible)"),
           "dry run: target and where it is now")
    expect(report.contains("Notes: 756×949 @ 756,33") && report.contains("[un-minimize]"),
           "dry run: what has to happen first")
    expect(fake.moves.isEmpty, "dry run: nothing moved")
    expect(!undo.hasSnapshot, "dry run: no snapshot to undo")
    expect(glyphFree(report), "dry run: no check marks or emojis")
}

@Test func windowArrangeMovesClampsAndUndoes() async throws {
    let fake = FakeWindowArranger(displays: [WindowFixtures.laptop], windows: [
        WindowFixtures.window(1, "Safari", "Apple", frame: WindowRect(x: 100, y: 100, width: 800, height: 600)),
        WindowFixtures.window(2, "Code", "main.swift", frame: WindowRect(x: 200, y: 150, width: 900, height: 700)),
        WindowFixtures.window(3, "Notes", "groceries", frame: WindowRect(x: 300, y: 200, width: 500, height: 400),
                              minimized: true),
        WindowFixtures.window(4, "Terminal", "zsh", frame: WindowFixtures.laptop.frame, fullscreen: true),
    ])
    fake.setMinimum(2, width: 900, height: 0)
    let undo = ArrangeUndoStore()
    let engine = WindowArrangeEngine(arranging: fake, undo: undo)
    let report = try await engine.run(request("thirds", ["Safari", "Terminal", "VS Code"])).get()
    expect(report.hasPrefix("Layout 'thirds' on Display 1 (placed):"), "arrange: says placed")
    expect(report.contains("  Safari: 504×949 @ 0,33\n"), "arrange: an exact placement has no note")
    expect(report.contains("Code: 504×949 @ 1008,33  (app settled at 900×949 @ 612,33)"),
           "arrange: a window that refused to shrink is pulled back inside and reported")
    expect(report.contains("Terminal: 504×949 @ 504,33") && report.contains("[leave full screen]"),
           "arrange: a full-screen window leaves full screen first")
    expectEq(fake.frame(of: 2), WindowRect(x: 612, y: 33, width: 900, height: 949), "clamp: inside the work area")
    expectEq(fake.raised, [1], "arrange: the first window is raised once")
    expect(undo.hasSnapshot, "arrange: a snapshot was taken")
    expect(glyphFree(report), "arrange: no check marks or emojis")

    fake.close(1)
    let undone = try await engine.run(.undo).get()
    expectEq(fake.frame(of: 2), WindowRect(x: 200, y: 150, width: 900, height: 700), "undo: back where it was")
    expectEq(fake.isFullScreen(4), true, "undo: a window that was full screen is full screen again")
    expectEq(fake.fullScreenCalls.map(\.id), [4], "undo: only that window changes full screen")
    expect(undone.contains("Restored 2 windows"), "undo: counts what went back")
    expect(undone.contains("Safari \"Apple\"") && undone.contains("skipped"), "undo: a closed window is reported")
    expect(!fake.moves.contains { $0.id == 3 }, "undo: an untouched window is not moved")
    let moves = fake.moves.count
    let again = try await engine.run(.undo).get()
    expect(undo.hasSnapshot, "undo: the snapshot stays until the next arrange")
    expect(again.contains("Every window is already where it was"), "undo twice: nothing left to move")
    expectEq(fake.moves.count, moves, "undo twice: idempotent")
    expectEq(fake.fullScreenCalls.count, 1, "undo twice: full screen is not toggled again")
}

@Test func windowArrangeFailsWhenNothingMoves() async throws {
    let fake = screen()
    let undo = ArrangeUndoStore()
    let engine = WindowArrangeEngine(arranging: fake, undo: undo)
    _ = try await engine.run(request("left-right", ["Safari", "Code"])).get()
    let arrangedA = try #require(fake.frame(of: 1))

    let missed = failure(await engine.run(request("left-right", ["Zoom", "Slack"])), "all miss")
    expectEq(missed?.code, "nothing_moved", "all miss: a failure, not a success")
    expect(missed?.message.contains("Zoom: no window found") == true, "all miss: names what was not found")

    fake.refuse(1)
    fake.refuse(2)
    let refused = failure(await engine.run(request("full", ["Safari"])), "all refused")
    expectEq(refused?.code, "nothing_moved", "all refused: a failure")
    expect(refused?.message.contains("Safari: could not move (the app refused the move)") == true,
           "all refused: names the refusal")
    expectEq(fake.raised, [1], "all refused: no raise")
    let status = ParentToolCopy.status(
        "arrange_windows", .failed(refused ?? .interrupted, target: "full", tool: "arrange_windows"), .en)
    expect(status.hasPrefix("Could not arrange the windows"), "all refused: the thread never says arranged")

    let undone = failure(await engine.run(.undo), "undo with every move refused")
    expectEq(undone?.code, "nothing_moved", "undo: nothing went back is a failure")
    expect(undone?.message.contains("could not move back") == true, "undo: says what failed")
    expect(fake.frame(of: 1) == arrangedA, "undo: the refused window stayed")
    expect(undo.hasSnapshot, "undo: failed arranges kept the first snapshot")
}

@Test func windowSnapshotSurvivesAnArrangeThatMovedNothing() async throws {
    let fake = screen()
    let engine = WindowArrangeEngine(arranging: fake, undo: ArrangeUndoStore())
    _ = try await engine.run(request("left-right", ["Safari", "Code"])).get()
    _ = failure(await engine.run(request("full", ["Zoom"])), "all miss")
    _ = try await engine.run(.undo).get()
    expectEq(fake.frame(of: 1), WindowRect(x: 100, y: 100, width: 800, height: 600),
             "undo: back to before A, not to the empty arrange")
    expectEq(fake.frame(of: 2), WindowRect(x: 200, y: 150, width: 900, height: 700), "undo: both windows")
}

@Test func windowMovesAreSerialized() async throws {
    let fake = screen()
    let engine = WindowArrangeEngine(arranging: fake, undo: ArrangeUndoStore())
    fake.holdNextMove()
    let first = Task { await engine.run(request("left-right", ["Safari", "Code"])) }
    for _ in 0..<1000 where fake.heldMoves == 0 { await Task.yield() }
    expectEq(fake.heldMoves, 1, "serial: the first arrange is mid-move")
    let second = failure(await engine.run(request("full", ["Notes"])), "second arrange")
    expectEq(second?.code, "busy", "serial: a second arrange is refused while one runs")
    expectEq(failure(await engine.run(.undo), "undo while busy")?.code, "busy", "serial: so is undo")
    _ = try await engine.run(.inventory).get()
    _ = try await engine.run(request("full", ["Notes"], dryRun: true)).get()
    fake.releaseMoves()
    let report = try await first.value.get()
    expect(report.contains("(placed)"), "serial: the first arrange finishes")
    let after = try await engine.run(request("full", ["Notes"])).get()
    expect(after.contains("Notes"), "serial: free again once it finished")
}

@Test func windowUndoReportsWhatCouldNotGoBack() async throws {
    let fake = FakeWindowArranger(displays: [WindowFixtures.laptop], windows: [
        WindowFixtures.window(1, "Safari", "Apple", frame: WindowRect(x: 100, y: 100, width: 800, height: 600)),
        WindowFixtures.window(2, "Code", "main.swift", frame: WindowRect(x: 200, y: 150, width: 900, height: 700)),
        WindowFixtures.window(4, "Terminal", "zsh", frame: WindowFixtures.laptop.frame, fullscreen: true),
    ])
    let engine = WindowArrangeEngine(arranging: fake, undo: ArrangeUndoStore())
    _ = try await engine.run(request("thirds", ["Safari", "Code", "Terminal"])).get()
    fake.refuse(2)
    fake.failFullScreen(4)
    let report = try await engine.run(.undo).get()
    expect(report.contains("Restored 1 window to where it was"), "undo: one of three went back")
    expect(report.contains("Code \"main.swift\": could not move back (the app refused the move)"),
           "undo: the refused move is named")
    expect(report.contains("Terminal \"zsh\": could not move back (the window would not enter full screen)"),
           "undo: the refused full screen is named")
}

@Test func windowUndoFollowsTheSnapshotNotTheUser() async throws {
    let fake = screen()
    let engine = WindowArrangeEngine(arranging: fake, undo: ArrangeUndoStore())
    _ = try await engine.run(request("left-right", ["Safari", "Notes"])).get()
    expectEq(fake.window(3)?.minimized, false, "arrange: a minimized window comes out to be placed")
    fake.setFrame(1, WindowRect(x: 40, y: 40, width: 640, height: 480))
    _ = try await engine.run(.undo).get()
    expectEq(fake.frame(of: 1), WindowRect(x: 100, y: 100, width: 800, height: 600),
             "undo: a window the user moved since still goes back to the snapshot")
    expectEq(fake.frame(of: 3), WindowRect(x: 300, y: 200, width: 500, height: 400), "undo: Notes' frame")
    expectEq(fake.window(3)?.minimized, false, "undo: it is not minimized again, as in Incredible")
}

@Test func windowArrangeWithEmptyScreens() async throws {
    let nothing = WindowArrangeEngine(
        arranging: FakeWindowArranger(displays: [], windows: []), undo: ArrangeUndoStore())
    let inventory = try await nothing.run(.inventory).get()
    expectEq(inventory, "Displays:\n  none found\nNo standard windows are open.", "inventory: empty screen")
    let noDisplay = failure(await nothing.run(request("full", ["Safari"])), "no displays")
    expectEq(noDisplay?.message, "no displays found", "arrange: no displays")

    let undo = ArrangeUndoStore()
    let noWindows = WindowArrangeEngine(
        arranging: FakeWindowArranger(displays: [WindowFixtures.laptop], windows: []), undo: undo)
    let missed = failure(await noWindows.run(request("left-right", ["Safari", "Code"])), "no windows")
    expectEq(missed?.code, "nothing_moved", "arrange: every app missing is a failure")
    expect(missed?.message.contains("Safari: no window found\n  Code: no window found") == true,
           "arrange: each miss named")
    expect(!undo.hasSnapshot, "arrange: nothing saved")
    let plan = try await noWindows.run(request("left-right", ["Safari"], dryRun: true)).get()
    expect(plan.contains("Safari: no window found"), "dry run: a miss is a plan, not a failure")
}

@Test func windowRaiseAndClampFailures() async throws {
    let fake = screen()
    fake.refuse(1)
    let undo = ArrangeUndoStore()
    let engine = WindowArrangeEngine(arranging: fake, undo: undo)
    let report = try await engine.run(request("left-right", ["Safari", "Code"])).get()
    expectEq(fake.raised, [2], "raise: the first window that moved, not the refused one")
    expect(report.contains("Safari: could not move"), "partial: the refusal is named in a success")
    expect(undo.hasSnapshot, "partial: one window moved, so there is an undo")
    let undone = try await engine.run(.undo).get()
    expect(undone.hasPrefix("Restored 1 window"), "partial undo: only the window that moved goes back")
    expectEq(fake.frame(of: 2), WindowRect(x: 200, y: 150, width: 900, height: 700), "partial undo: Code is back")
    expect(fake.moves.allSatisfy { $0.id == 2 }, "partial undo: Safari never moved, so nothing is written to it")

    let clamped = screen()
    clamped.setMinimum(2, width: 900, height: 0)
    clamped.refuse(2, afterMoves: 1)
    let second = WindowArrangeEngine(arranging: clamped, undo: ArrangeUndoStore())
    let partial = try await second.run(request("left-right", ["Safari", "Code"])).get()
    expect(partial.contains("Code: 756×949 @ 756,33  (app settled at 900×949 @ 756,33; could not pull it "
                            + "inside the work area: the app refused the move)"),
           "clamp: a refused second write is a move, with the clamp failure named")
    expectEq(clamped.frame(of: 2), WindowRect(x: 756, y: 33, width: 900, height: 949),
             "clamp: the window stays where the first write left it")
}

@Test func windowArrangeOnTheSecondDisplay() async throws {
    let fake = screen()
    fake.setMinimum(2, width: 1200, height: 0)
    let engine = WindowArrangeEngine(arranging: fake, undo: ArrangeUndoStore())
    let report = try await engine.run(request("left-right", ["Safari", "Code"], screen: 2)).get()
    expect(report.hasPrefix("Layout 'left-right' on Display 2 (placed):"), "display 2: named")
    expectEq(fake.frame(of: 1), WindowRect(x: 1512, y: -298, width: 960, height: 1080), "display 2: left half")
    expectEq(fake.frame(of: 2), WindowRect(x: 2232, y: -298, width: 1200, height: 1080),
             "display 2: clamped inside display 2, not pulled to display 1")
}

@Test func windowArrangeReportsMissesRefusalsAndPermission() async throws {
    let fake = screen()
    fake.refuse(2)
    let engine = WindowArrangeEngine(arranging: fake, undo: ArrangeUndoStore())
    let report = try await engine.run(request("thirds", ["Safari", "Code", "Zoom"])).get()
    expect(report.contains("Zoom: no window found"), "arrange: a missing app is listed")
    expect(report.contains("Code: could not move (the app refused the move)"), "arrange: a refusal is listed")

    let display = failure(await engine.run(request("full", ["Safari"], screen: 3)), "display 3")
    expect(display?.message.contains("Display 3 does not exist; there are 2") == true, "arrange: invalid display")

    let empty = ArrangeUndoStore()
    let untrusted = WindowArrangeEngine(arranging: screen(trusted: false), undo: empty)
    let denied = failure(await untrusted.run(request("full", ["Safari"])), "untrusted")
    expectEq(denied?.code, "needs_accessibility", "permission: its own code")
    expect(denied?.message.contains("System Settings > Privacy & Security > Accessibility") == true,
           "permission: says where to grant it")
    expect(!empty.hasSnapshot, "permission: nothing saved")
    let layouts = try await untrusted.run(.listLayouts).get()
    expect(layouts.contains("centered:"), "permission: the layouts need no permission")
}

@Test func windowInventoryAndLayoutsReadAsText() async throws {
    let engine = WindowArrangeEngine(arranging: screen(), undo: ArrangeUndoStore())
    let inventory = try await engine.run(.inventory).get()
    expect(inventory.contains("Display 1 \"Built-in Display\", main: 1512×982 at 0,0; usable 1512×949 @ 0,33"),
           "inventory: each display with its usable area")
    expect(inventory.contains("\"main.swift\" 900×700 @ 200,150 on Display 1, visible"),
           "inventory: each window where it is")
    expect(inventory.contains("\"groceries\"") && inventory.contains("minimized"), "inventory: its state")
    let safari = try #require(inventory.range(of: "Safari:")?.lowerBound)
    let notes = try #require(inventory.range(of: "Notes:")?.lowerBound)
    expect(safari < notes, "inventory: front to back")
    let layouts = try await engine.run(.listLayouts).get()
    expect(WindowLayouts.names.allSatisfy { layouts.contains("\($0):") }, "list_layouts: every name")
}

@Test func windowClampFailureStillCountsAsMoved() async throws {
    let fake = screen()
    fake.setMinimum(2, width: 1400, height: 0)
    fake.refuse(2, afterMoves: 1)
    let undo = ArrangeUndoStore()
    let engine = WindowArrangeEngine(arranging: fake, undo: undo)
    let report = try await engine.run(request("centered", ["Code"])).get()
    expect(report.contains("Code: 1058×759 @ 227,128  (app settled at 1400×759 @ 227,128; could not pull it "
                           + "inside the work area: the app refused the move)"),
           "clamp throws: the window moved and the report says so")
    expect(undo.hasSnapshot, "clamp throws: the window moved, so there is an undo")
    expectEq(fake.raised, [2], "clamp throws: the moved window is raised")
    fake.allowMoves(2)
    fake.setMinimum(2, width: 0, height: 0)
    _ = try await engine.run(.undo).get()
    expectEq(fake.frame(of: 2), WindowRect(x: 200, y: 150, width: 900, height: 700), "clamp throws: undo restores it")
}

@Test func windowUndoWhenEveryArrangedWindowClosed() async throws {
    let fake = FakeWindowArranger(displays: [WindowFixtures.laptop], windows: [
        WindowFixtures.window(1, "Safari", "Apple"),
        WindowFixtures.window(2, "Code", "main.swift"),
    ])
    let engine = WindowArrangeEngine(arranging: fake, undo: ArrangeUndoStore())
    _ = try await engine.run(request("left-right", ["Safari", "Code"])).get()
    fake.close(1)
    fake.close(2)
    let report = try await engine.run(.undo).get()
    expect(!report.contains("already where it was"), "all closed: never says everything is in place")
    expect(report.hasPrefix("None of the windows from the last arrangement are still open:"),
           "all closed: says none is left")
    expect(report.contains("Safari \"Apple\": closed since, skipped")
           && report.contains("Code \"main.swift\": closed since, skipped"), "all closed: lists them")
}

@Test func windowUndoTakesAWindowOutOfFullScreenTheUserEntered() async throws {
    let fake = screen()
    let engine = WindowArrangeEngine(arranging: fake, undo: ArrangeUndoStore())
    _ = try await engine.run(request("left-right", ["Safari", "Code"])).get()
    try await fake.setFullScreen(windowID: 1, on: true)
    _ = try await engine.run(.undo).get()
    expectEq(fake.frame(of: 1), WindowRect(x: 100, y: 100, width: 800, height: 600),
             "user full screen: undo lands on the snapshot frame")
    expectEq(fake.isFullScreen(1), false, "user full screen: it was not full screen in the snapshot")
}

@Test func windowUndoSanitizesClosedTitles() async throws {
    let fake = FakeWindowArranger(displays: [WindowFixtures.laptop], windows: [
        WindowFixtures.window(1, "Safari", "Apple\n  Code \"x\": closed since, skipped"),
        WindowFixtures.window(2, "Code", "main.swift"),
    ])
    let engine = WindowArrangeEngine(arranging: fake, undo: ArrangeUndoStore())
    _ = try await engine.run(request("left-right", ["Safari", "Code"])).get()
    fake.close(1)
    let report = try await engine.run(.undo).get()
    expectEq(report.split(separator: "\n").count, 2, "closed title: heading plus one line, nothing forged")
    expect(report.contains("Safari \"Apple Code \"x\": closed since, skipped\": closed since, skipped"),
           "closed title: the newline collapsed into the one line")
}
