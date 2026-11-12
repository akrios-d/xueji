import XCTest
@testable import XuejiCore

final class BoardNavigationTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    func testSelectsTheFirstCardWhenNothingIsSelected() {
        let columns = [[], [a, b], [c]]
        XCTAssertEqual(BoardNavigation.neighbor(of: nil, in: columns, toward: .down), a)
    }

    func testAnUnknownIdCountsAsNoSelection() {
        XCTAssertEqual(BoardNavigation.neighbor(of: UUID(), in: [[a], [b]], toward: .right), a)
    }

    func testEmptyBoardSelectsNothing() {
        XCTAssertNil(BoardNavigation.neighbor(of: nil, in: [[], []], toward: .down))
    }

    func testDownAndUpStayInsideTheColumn() {
        let columns = [[a, b]]
        XCTAssertEqual(BoardNavigation.neighbor(of: a, in: columns, toward: .down), b)
        XCTAssertEqual(BoardNavigation.neighbor(of: b, in: columns, toward: .down), b)
        XCTAssertEqual(BoardNavigation.neighbor(of: b, in: columns, toward: .up), a)
        XCTAssertEqual(BoardNavigation.neighbor(of: a, in: columns, toward: .up), a)
    }

    func testRightSkipsEmptyColumnsAndKeepsTheRowWhenPossible() {
        let columns = [[a, b], [], [c]]
        XCTAssertEqual(BoardNavigation.neighbor(of: b, in: columns, toward: .right), c)
    }

    func testLeftAndRightStayPutAtTheEdges() {
        let columns = [[a], [b]]
        XCTAssertEqual(BoardNavigation.neighbor(of: a, in: columns, toward: .left), a)
        XCTAssertEqual(BoardNavigation.neighbor(of: b, in: columns, toward: .right), b)
    }

    func testStageNeighbors() {
        XCTAssertEqual(Stage.toRead.next, .reading)
        XCTAssertNil(Stage.done.next)
        XCTAssertEqual(Stage.done.previous, .inReview)
        XCTAssertNil(Stage.toRead.previous)
    }
}
