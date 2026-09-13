import SwiftUI

struct RuleConflictNotice: View {
    let conflict: RuleConflict
    let earlierDestination: String
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(conflict.title, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(conflict.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !compact {
                Text("Earlier destination: \(earlierDestination)")
                    .font(.caption.weight(.medium))
                Text("Move this rule above it, narrow the earlier rule, or disable one of them. You can still save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("\(conflict.explanation) Earlier destination: \(earlierDestination)")
    }
}
