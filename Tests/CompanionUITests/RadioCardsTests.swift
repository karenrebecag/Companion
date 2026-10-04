@testable import CompanionUI
import CompanionTestKit
import Testing

// Arc's radio-cards (uiarc.dev, free registry: radio-cards.json): one tab
// stop, arrows select and wrap, Home and End jump to the ends. The rules
// live in a value so they are tested without a window.

@Suite("radio cards") struct RadioCardsTests {
    @Test func arrowsSelectAndWrapBothWays() {
        var selection = RadioCardsSelection(options: ["a", "b", "c"], selected: "c")
        #expect(selection.move(by: 1) == "a", "past the last wraps to the first")
        #expect(selection.move(by: -1) == "c", "before the first wraps to the last")
        #expect(selection.move(by: -1) == "b")
    }

    @Test func homeAndEndJumpToTheEnds() {
        var selection = RadioCardsSelection(options: ["a", "b", "c"], selected: "b")
        #expect(selection.first() == "a")
        #expect(selection.last() == "c")
    }

    @Test func aSelectionOutsideTheCardsStartsFromAnEnd() {
        var down = RadioCardsSelection(options: ["a", "b"], selected: "z")
        #expect(down.move(by: 1) == "a", "down from nothing lands on the first card")
        var up = RadioCardsSelection(options: ["a", "b"], selected: "z")
        #expect(up.move(by: -1) == "b", "up from nothing lands on the last card")
    }

    @Test func selectIgnoresAValueThatIsNotACard() {
        var selection = RadioCardsSelection(options: ["a", "b"], selected: "a")
        selection.select("z")
        #expect(selection.selected == "a")
        selection.select("b")
        #expect(selection.selected == "b")
    }

    @Test func noCardsLeavesTheSelectionAlone() {
        var selection = RadioCardsSelection(options: [String](), selected: "a")
        #expect(selection.move(by: 1) == "a")
        #expect(selection.first() == "a")
        #expect(selection.last() == "a")
    }

    @Test func aCardReadsItsLabelThenWhatSetsItApart() {
        #expect(RadioCardOption(value: 1, label: "Ana", meta: "Default").accessibilityLabel == "Ana, Default")
        #expect(RadioCardOption(value: 1, label: "Ana", description: "id", meta: nil).accessibilityLabel
            == "Ana, id")
        #expect(RadioCardOption(value: 1, label: "Ana").accessibilityLabel == "Ana")
    }

    @MainActor @Test func reduceMotionDropsTheRingAnimation() {
        expect(RadioCards<Int>.animation(reduceMotion: true) == nil, "reduce motion: the ring jumps")
        expect(RadioCards<Int>.animation(reduceMotion: false) != nil, "otherwise it glides")
    }
}
