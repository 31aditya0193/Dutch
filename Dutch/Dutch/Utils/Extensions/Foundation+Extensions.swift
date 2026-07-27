import Foundation

// MARK: - Decimal Precision

extension Double {
    /// Rounds to a specific number of decimal places.
    func rounded(to places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

// MARK: - Collection Safe Access

extension Collection {
    /// Safely access an index, returning `nil` if out of bounds.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Date Formatting

extension Date {
    /// Short, readable representation for display in lists.
    var shortFormatted: String {
        self.formatted(date: .abbreviated, time: .omitted)
    }
}
