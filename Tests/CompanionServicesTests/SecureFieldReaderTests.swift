import CoreGraphics
import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// The walk runs against a fake tree, so each unreadable answer from the
// Accessibility API can be scripted without a live app.

@Test func secureFieldReaderTests() {
    testASubroleReadThatTimesOutWithdrawsTheFrame()
    testAnEmptyTreeOfAnAppWithAWindowOnScreenWithdrawsTheFrame()
    testAnUnbuiltTreeIsReadAgainAfterSettling()
    testUnsupportedChildrenAreALeafNotAFailure()
    testASecureFieldBoxIsReturned()
}

private let fieldBox = CGRect(x: 40, y: 60, width: 200, height: 24)

private struct FakeNode: Sendable {
    var role: AXAttempt<String>
    var subrole: AXAttempt<String> = .absent
    var frame: CGRect?
    var children: AXAttempt<[FakeNode]> = .absent
}

private let secureField = FakeNode(
    role: .value("AXTextField"), subrole: .value("AXSecureTextField"), frame: fieldBox)

/// Each window read pops the next scripted answer; the last one repeats.
private final class FakeTree: SecureFieldTree {
    typealias Node = FakeNode
    private var windowReads: [AXAttempt<[FakeNode]>]
    private(set) var settles = 0

    init(windowReads: [AXAttempt<[FakeNode]>]) {
        self.windowReads = windowReads
    }

    func prime(_ pid: pid_t) {}
    func settle() { settles += 1 }

    func windows(_ pid: pid_t) -> AXAttempt<[FakeNode]> {
        windowReads.count > 1 ? windowReads.removeFirst() : (windowReads.first ?? .absent)
    }

    func role(_ node: FakeNode) -> AXAttempt<String> { node.role }
    func subrole(_ node: FakeNode) -> AXAttempt<String> { node.subrole }
    func frame(_ node: FakeNode) -> CGRect? { node.frame }
    func children(_ node: FakeNode) -> AXAttempt<[FakeNode]> { node.children }
}

private func isIncomplete(_ read: SecureFieldMask.Read) -> Bool {
    if case .incomplete = read { return true }
    return false
}

func testASubroleReadThatTimesOutWithdrawsTheFrame() {
    // A password field whose subrole read timed out must not look like a
    // plain text field: the walk cannot tell, so the frame is withheld.
    let window = FakeNode(role: .value("AXTextField"), subrole: .failed, frame: fieldBox)
    let tree = FakeTree(windowReads: [.value([window])])
    let read = SecureFieldReader.read(pids: [1], shown: [1], tree: tree)
    expect(isIncomplete(read), "lector: un subrole que agota el tiempo retira el cuadro")
}

func testAnEmptyTreeOfAnAppWithAWindowOnScreenWithdrawsTheFrame() {
    // Chromium answers an empty tree until it is primed: an empty answer for
    // an app with a window on screen proves nothing about its secure fields.
    let tree = FakeTree(windowReads: [.value([])])
    let read = SecureFieldReader.read(pids: [1], shown: [1], tree: tree)
    expect(isIncomplete(read), "lector: arbol vacio con ventana en pantalla retira el cuadro")
}

func testAnUnbuiltTreeIsReadAgainAfterSettling() {
    let tree = FakeTree(windowReads: [.value([]), .value([FakeNode(
        role: .value("AXWindow"), children: .value([secureField]))])])
    let read = SecureFieldReader.read(pids: [1], shown: [1], tree: tree)
    expectEq(read, .fields([fieldBox]), "lector: el arbol aun no armado se vuelve a leer")
    expectEq(tree.settles, 1, "lector: una sola espera antes de releer")
}

func testUnsupportedChildrenAreALeafNotAFailure() {
    let group = FakeNode(role: .value("AXGroup"), children: .unsupported)
    let tree = FakeTree(windowReads: [.value([group, secureField])])
    let read = SecureFieldReader.read(pids: [1], shown: [], tree: tree)
    expectEq(read, .fields([fieldBox]),
             "lector: hijos no soportados son hoja, no retiran el cuadro")
}

func testASecureFieldBoxIsReturned() {
    let tree = FakeTree(windowReads: [.value([secureField])])
    let read = SecureFieldReader.read(pids: [1], shown: [1], tree: tree)
    expectEq(read, .fields([fieldBox]), "lector: la caja de un campo seguro sale")
}
