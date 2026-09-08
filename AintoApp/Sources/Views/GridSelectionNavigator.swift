enum MainSearchGridMetrics {
    static let columnCount = 7
    static let collapsedRowCount = 2
}

enum ApplicationGridPresentation {
    static func visibleItems<Item>(
        from items: [Item],
        isExpanded: Bool,
        columnCount: Int
    ) -> [Item] {
        guard !isExpanded else { return items }
        guard columnCount > 0 else { return [] }
        return Array(items.prefix(columnCount * MainSearchGridMetrics.collapsedRowCount))
    }

    static func collapsedItems<Item, ID: Hashable>(
        recent: [Item],
        all: [Item],
        maximumCount: Int,
        id: (Item) -> ID
    ) -> [Item] {
        guard maximumCount > 0 else { return [] }

        var seen = Set<ID>()
        var combined: [Item] = []
        for item in recent + all {
            guard combined.count < maximumCount else { break }
            guard seen.insert(id(item)).inserted else { continue }
            combined.append(item)
        }
        return combined
    }
}

enum GridNavigationDirection {
    case left
    case right
    case up
    case down
}

enum GridSelectionNavigator {
    static func destination(
        from currentIndex: Int,
        itemCount: Int,
        columnCount: Int,
        direction: GridNavigationDirection
    ) -> Int {
        guard itemCount > 0 else { return 0 }

        let lastIndex = itemCount - 1
        guard (0...lastIndex).contains(currentIndex) else {
            return min(max(currentIndex, 0), lastIndex)
        }
        guard columnCount > 0 else { return currentIndex }

        switch direction {
        case .left:
            return max(currentIndex - 1, 0)
        case .right:
            return min(currentIndex + 1, lastIndex)
        case .up:
            return max(currentIndex - columnCount, 0)
        case .down:
            return min(currentIndex + columnCount, lastIndex)
        }
    }
}
