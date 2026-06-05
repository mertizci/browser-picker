import Foundation

/// A minimal semantic version (major.minor.patch) that is `Comparable`.
///
/// Accepts GitHub tag forms like `v1.2.3` and `1.2` (missing components are
/// treated as zero). Pre-release / build metadata suffixes are ignored.
struct SemanticVersion: Comparable, CustomStringConvertible {
    let components: [Int]

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }

        // Drop any pre-release / build metadata (e.g. "1.2.3-beta+5").
        if let cut = text.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            text = String(text[..<cut])
        }

        let parsed = text.split(separator: ".").map { Int($0) }
        guard !parsed.isEmpty, parsed.allSatisfy({ $0 != nil }) else { return nil }
        components = parsed.compactMap { $0 }
    }

    private func component(at index: Int) -> Int {
        index < components.count ? components[index] : 0
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = lhs.component(at: index)
            let right = rhs.component(at: index)
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count where lhs.component(at: index) != rhs.component(at: index) {
            return false
        }
        return true
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }
}
