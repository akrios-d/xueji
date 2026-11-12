import Foundation

public enum BoardDirection: Sendable { case left, right, up, down }

/// Keyboard navigation over a board, as pure logic so it can be tested without any UI.
public enum BoardNavigation {
    /// - Parameters:
    ///   - current: the selected card, if any (an id that is no longer on the board counts as none).
    ///   - columns: the card ids of each column, top to bottom.
    /// - Returns: the card to select next, or `nil` when the board has no cards.
    public static func neighbor(of current: UUID?, in columns: [[UUID]], toward direction: BoardDirection) -> UUID? {
        guard let (column, row) = position(of: current, in: columns) else {
            return columns.first(where: { !$0.isEmpty })?.first
        }
        switch direction {
        case .up:
            return columns[column][max(row - 1, 0)]
        case .down:
            return columns[column][min(row + 1, columns[column].count - 1)]
        case .left, .right:
            let step = direction == .left ? -1 : 1
            var next = column + step
            while columns.indices.contains(next) {
                if !columns[next].isEmpty {
                    return columns[next][min(row, columns[next].count - 1)]
                }
                next += step
            }
            return columns[column][row]
        }
    }

    private static func position(of id: UUID?, in columns: [[UUID]]) -> (column: Int, row: Int)? {
        guard let id else { return nil }
        for (column, ids) in columns.enumerated() {
            if let row = ids.firstIndex(of: id) { return (column, row) }
        }
        return nil
    }
}

extension Stage {
    /// The next stage on the board, or `nil` at the end.
    public var next: Stage? {
        guard let index = Stage.allCases.firstIndex(of: self), index + 1 < Stage.allCases.count else { return nil }
        return Stage.allCases[index + 1]
    }

    /// The previous stage on the board, or `nil` at the start.
    public var previous: Stage? {
        guard let index = Stage.allCases.firstIndex(of: self), index > 0 else { return nil }
        return Stage.allCases[index - 1]
    }
}
