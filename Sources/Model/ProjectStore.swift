import Foundation

/// The WIP gate: at most `cap` projects may be in flight at once.
///
/// Mirrors `UsageArchive`'s conventions: a plain `Codable` array under one
/// `UserDefaults` key, injected defaults so tests and the CLI can point at
/// their own domain without touching the app's.
///
/// Slot rules, as the plan decided them:
/// - A deferred project does **not** hold a slot — `defer` frees one
///   immediately ("I'll be free by then").
/// - When the defer date passes, the project returns to `.active` and counts
///   again. That can push the count over the cap; new adds stay blocked until
///   the overage clears.
struct ProjectStore {
    /// The WIP ceiling. One constant, so the model, the CLI, the notch and
    /// the docs cannot drift apart.
    static let cap = 5
    static let defaultsKey = "projectGate"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Commands

    /// Open a new project. Fails with `.capReached` while `cap` projects are
    /// active — deferred projects do not hold a slot. A blank title is a usage
    /// error, not a project.
    @discardableResult
    func add(title: String, now: Date = Date()) -> Result<Void, ProjectGateError> {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.invalidTitle) }
        var projects = load()
        expireDeferred(in: &projects, now: now)
        guard activeCount(in: projects) < Self.cap else {
            return .failure(.capReached)
        }
        projects.append(Project(title: trimmed,
                                createdAt: now))
        save(projects)
        return .success(())
    }

    /// Mark a project completed, freeing its slot.
    @discardableResult
    func complete(id: UUID, now: Date = Date()) -> Result<Void, ProjectGateError> {
        var projects = load()
        expireDeferred(in: &projects, now: now)
        guard let index = projects.firstIndex(where: { $0.id == id }) else {
            return .failure(.notFound)
        }
        projects[index].status = .completed
        projects[index].completedAt = projects[index].completedAt ?? now
        save(projects)
        return .success(())
    }

    /// Park a project until a future date, freeing its slot immediately.
    /// A completed project is finished — it cannot be parked back into flight.
    @discardableResult
    func `defer`(id: UUID, until: Date, now: Date = Date()) -> Result<Void, ProjectGateError> {
        guard until > now else { return .failure(.invalidDate) }
        var projects = load()
        expireDeferred(in: &projects, now: now)
        guard let index = projects.firstIndex(where: { $0.id == id }) else {
            return .failure(.notFound)
        }
        guard projects[index].status != .completed else {
            return .failure(.notFound)  // a completed project cannot be deferred
        }
        projects[index].status = .deferred
        projects[index].deferUntil = until
        projects[index].completedAt = nil
        save(projects)
        return .success(())
    }

    /// A deferred project whose date has passed is still to be done: it
    /// returns to `.active` and counts against the cap again. The cap may
    /// then be exceeded — new adds are blocked until the overage clears.
    func expireDeferred(now: Date = Date()) {
        var projects = load()
        expireDeferred(in: &projects, now: now)
        save(projects)
    }

    private func expireDeferred(in projects: inout [Project], now: Date) {
        for index in projects.indices where projects[index].status == .deferred {
            guard let until = projects[index].deferUntil, until <= now else { continue }
            projects[index].status = .active
            projects[index].deferUntil = nil
        }
    }

    private func activeCount(in projects: [Project]) -> Int {
        projects.filter { $0.status == .active }.count
    }

    // MARK: - Queries

    /// Find a project by id or by title (case- and accent-insensitive).
    func resolve(_ identifier: String) -> Project? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let projects = load()
        if let id = UUID(uuidString: trimmed) {
            return projects.first { $0.id == id }
        }
        return projects.first {
            $0.title.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    /// Every project, ordered for display: active by age first, then deferred
    /// by due date, then completed newest-first.
    func list() -> [Project] {
        let projects = load()
        return projects.sorted { a, b in
            let rank: (ProjectStatus) -> Int = { status in
                switch status {
                case .active:   return 0
                case .deferred: return 1
                case .completed: return 2
                }
            }
            let ra = rank(a.status), rb = rank(b.status)
            if ra != rb { return ra < rb }
            switch a.status {
            case .active:
                return a.createdAt < b.createdAt
            case .deferred:
                return (a.deferUntil ?? a.createdAt) < (b.deferUntil ?? b.createdAt)
            case .completed:
                return (a.completedAt ?? a.createdAt) > (b.completedAt ?? b.createdAt)
            }
        }
    }

    /// How many projects are open right now.
    func activeCount(now: Date = Date()) -> Int {
        var projects = load()
        expireDeferred(in: &projects, now: now)
        return projects.filter { $0.status == .active }.count
    }

    /// The four numbers the gate is about, in one value.
    func gateState(now: Date = Date()) -> ProjectGateState {
        var projects = load()
        expireDeferred(in: &projects, now: now)
        return ProjectGateState(
            active: projects.filter { $0.status == .active }.count,
            deferred: projects.filter { $0.status == .deferred }.count,
            completed: projects.filter { $0.status == .completed }.count,
            cap: Self.cap
        )
    }

    // MARK: - Persistence

    private func load() -> [Project] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let projects = try? JSONDecoder().decode([Project].self, from: data)
        else { return [] }
        return projects
    }

    private func save(_ projects: [Project]) {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
