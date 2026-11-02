import SwiftUI

enum StatusBadgeKind {
    case good
    case warning
    case neutral
    case error

    var label: String {
        switch self {
        case .good:
            return "Ready"
        case .warning:
            return "Needs Attention"
        case .neutral:
            return "Pending"
        case .error:
            return "Failed"
        }
    }

    var color: Color {
        switch self {
        case .good:
            return XNoxPalette.success
        case .warning:
            return XNoxPalette.warning
        case .neutral:
            return XNoxPalette.textSecondary
        case .error:
            return XNoxPalette.error
        }
    }
}

struct StatusBadge: View {
    let kind: StatusBadgeKind

    var body: some View {
        Text(kind.label)
            .font(XNoxTypography.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(kind.color.opacity(0.12))
            .foregroundStyle(kind.color)
            .overlay(
                Capsule()
                    .stroke(kind.color.opacity(0.35), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}
