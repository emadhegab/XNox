import Foundation

enum AppSection: String, CaseIterable, Hashable {
    case storage
    case simulator
    case history
    case settings

    var title: String {
        switch self {
        case .simulator:
            return "Simulators"
        case .storage:
            return "Storage"
        case .history:
            return "History"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .simulator:
            return "iphone.gen3"
        case .storage:
            return "externaldrive"
        case .history:
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .settings:
            return "gearshape"
        }
    }
}
