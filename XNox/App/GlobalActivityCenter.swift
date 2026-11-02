import Combine
import Foundation

@MainActor
final class GlobalActivityCenter: ObservableObject {
    struct Activity: Identifiable, Hashable {
        let id: UUID
        var title: String
        var detail: String?
        let source: String
        let startedAt: Date
    }

    @Published private(set) var activeActivities: [Activity] = []

    var hasActiveActivities: Bool {
        !activeActivities.isEmpty
    }

    var summaryLabel: String {
        let count = activeActivities.count
        return count == 1 ? "1 Task Running" : "\(count) Tasks Running"
    }

    var tooltipText: String {
        activeActivities
            .map { activity in
                if let detail = activity.detail, !detail.isEmpty {
                    return "\(activity.title) (\(activity.source))\n\(detail)"
                }
                return "\(activity.title) (\(activity.source))"
            }
            .joined(separator: "\n\n")
    }

    @discardableResult
    func begin(title: String, detail: String? = nil, source: String = "General") -> UUID {
        let entry = Activity(
            id: UUID(),
            title: title,
            detail: detail,
            source: source,
            startedAt: .now
        )
        activeActivities.append(entry)
        return entry.id
    }

    func update(id: UUID, title: String? = nil, detail: String? = nil) {
        guard let index = activeActivities.firstIndex(where: { $0.id == id }) else { return }
        if let title {
            activeActivities[index].title = title
        }
        if let detail {
            activeActivities[index].detail = detail
        }
    }

    func finish(id: UUID) {
        activeActivities.removeAll { $0.id == id }
    }
}
