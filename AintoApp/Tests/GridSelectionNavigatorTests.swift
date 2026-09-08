import Testing
@testable import AintoApp

@Test func movesHorizontallyWithinBounds() {
    #expect(GridSelectionNavigator.destination(from: 2, itemCount: 8, columnCount: 5, direction: .left) == 1)
    #expect(GridSelectionNavigator.destination(from: 2, itemCount: 8, columnCount: 5, direction: .right) == 3)
    #expect(GridSelectionNavigator.destination(from: 0, itemCount: 8, columnCount: 5, direction: .left) == 0)
    #expect(GridSelectionNavigator.destination(from: 7, itemCount: 8, columnCount: 5, direction: .right) == 7)
}

@Test func movesVerticallyByColumnCount() {
    #expect(GridSelectionNavigator.destination(from: 6, itemCount: 12, columnCount: 5, direction: .up) == 1)
    #expect(GridSelectionNavigator.destination(from: 1, itemCount: 12, columnCount: 5, direction: .down) == 6)
}

@Test func clampsVerticalMoveIntoIncompleteLastRow() {
    #expect(GridSelectionNavigator.destination(from: 4, itemCount: 8, columnCount: 5, direction: .down) == 7)
}

@Test func safelyHandlesEmptySingleAndInvalidColumnCounts() {
    #expect(GridSelectionNavigator.destination(from: 0, itemCount: 0, columnCount: 5, direction: .right) == 0)
    #expect(GridSelectionNavigator.destination(from: 0, itemCount: 1, columnCount: 5, direction: .down) == 0)
    #expect(GridSelectionNavigator.destination(from: 3, itemCount: 8, columnCount: 0, direction: .down) == 3)
    #expect(GridSelectionNavigator.destination(from: -1, itemCount: 8, columnCount: 5, direction: .right) == 0)
    #expect(GridSelectionNavigator.destination(from: 99, itemCount: 8, columnCount: 5, direction: .left) == 7)
}
