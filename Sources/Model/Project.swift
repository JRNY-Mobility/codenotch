import Foundation

/// Whether an open piece of work is being done, parked, or done.
enum ProjectStatus: String, Codable, Equatable {
    case active
    case deferred
    case completed

    /// The word the CLI prints and agents parse. Kept here rather than in the
    /// CLI so the store and the shell agree on what a status is called.
    var rawName: String { rawValue }

    /// The word the notch tooltip prints, English by default and localized by
    /// the caller (this type is shared with the CLI target, which has no L10n
    /// catalog — so the fallback string lives here and the UI wraps it).
    var displayName: String {
        switch self {
        case .active:   return "Active"
        case .deferred: return "Deferred"
        case .completed: return "Completed"
        }
    }
}

/// One tracked project in the gate.
struct Project: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var status: ProjectStatus
    var completedAt: Date?
    var deferUntil: Date?

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(),
         status: ProjectStatus = .active,
         completedAt: Date? = nil, deferUntil: Date? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.status = status
        self.completedAt = completedAt
        self.deferUntil = deferUntil
    }
}

/// The counts the gate reports, in one value the notch cell and the CLI can
/// both draw from.
struct ProjectGateState: Equatable {
    let active: Int
    let deferred: Int
    let completed: Int
    let cap: Int

    /// How many more projects may be opened before the cap blocks one.
    /// Negative when expired deferred projects have pushed the count over.
    var slotsLeft: Int { cap - active }
    var isAtCap: Bool { active >= cap }
}
