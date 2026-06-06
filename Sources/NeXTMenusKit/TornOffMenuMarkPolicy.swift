import Foundation

public struct TornOffMenuMarkUpdate {
    public let items: [MenuItem]
    public let handled: Bool
    public let changed: Bool

    public init(items: [MenuItem], handled: Bool, changed: Bool) {
        self.items = items
        self.handled = handled
        self.changed = changed
    }
}

public enum TornOffMenuMarkPolicy {
    private static let exclusiveCheckmark = "✓"

    public static func optimisticUpdate(
        items: [MenuItem],
        clickedIndex: Int,
        isKnownCheckable: Bool
    ) -> TornOffMenuMarkUpdate {
        guard items.indices.contains(clickedIndex) else {
            return TornOffMenuMarkUpdate(items: items, handled: false, changed: false)
        }

        if let identifier = normalizedIdentifier(items[clickedIndex].axIdentifier) {
            let groupIndices = items.indices.filter {
                normalizedIdentifier(items[$0].axIdentifier) == identifier
            }
            if groupIndices.count >= 2 {
                return radioUpdate(items: items, clickedIndex: clickedIndex, groupIndices: groupIndices)
            }
        }

        let clickedMark = normalizedMark(items[clickedIndex].markChar)
        guard clickedMark == exclusiveCheckmark || (clickedMark == nil && isKnownCheckable) else {
            return TornOffMenuMarkUpdate(items: items, handled: false, changed: false)
        }

        var updatedItems = items
        updatedItems[clickedIndex].markChar = clickedMark == exclusiveCheckmark ? nil : exclusiveCheckmark
        return TornOffMenuMarkUpdate(items: updatedItems, handled: true, changed: true)
    }

    private static func radioUpdate(
        items: [MenuItem],
        clickedIndex: Int,
        groupIndices: [Int]
    ) -> TornOffMenuMarkUpdate {
        var updatedItems = items
        var changed = false

        if normalizedMark(updatedItems[clickedIndex].markChar) != exclusiveCheckmark {
            updatedItems[clickedIndex].markChar = exclusiveCheckmark
            changed = true
        }

        for index in groupIndices where index != clickedIndex {
            if normalizedMark(updatedItems[index].markChar) == exclusiveCheckmark {
                updatedItems[index].markChar = nil
                changed = true
            }
        }

        return TornOffMenuMarkUpdate(items: updatedItems, handled: true, changed: changed)
    }

    private static func normalizedIdentifier(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedMark(_ mark: String?) -> String? {
        guard let mark else { return nil }
        let trimmed = mark.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
