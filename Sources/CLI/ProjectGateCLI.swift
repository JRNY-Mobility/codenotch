import Foundation

/// The `codenotch project` command surface.
///
/// Kept free of top-level code so the same file compiles into the app and the
/// test bundle as well as the CLI binary — the tests drive it directly, and
/// the binary's `main.swift` is only the four lines that hand `argv` over.
///
/// Exit codes are the contract agents rely on:
/// - `0` — the command did what it was asked.
/// - `1` — an expected refusal: cap reached, nothing matched, bad defer date.
/// - `2` — a usage error: unknown command or missing arguments.
enum ProjectGateCLI {
    static let exitOK: Int32 = 0
    static let exitFailure: Int32 = 1
    static let exitUsage: Int32 = 2

    /// The preferences domain the app itself writes to, so a shell-side gate
    /// command and the notch read one list. Non-sandboxed, so the suite name
    /// resolves to the same `~/Library/Preferences/com.vinz.codenotch.plist`
    /// the app's `UserDefaults.standard` uses.
    static let appDefaultsSuite = "com.vinz.codenotch"

    // MARK: - Entry

    static func run(
        arguments: [String],
        store: ProjectStore,
        now: Date = Date(),
        stdout: (String) -> Void = { print($0) },
        stderr: (String) -> Void = { Self.writeStderr($0) }
    ) -> Int32 {
        // `codenotch project <cmd>` and `codenotch <cmd>` are both accepted;
        // the binary's own argv starts with the "project" subcommand.
        var args = arguments
        if args.first == "project" { args.removeFirst() }
        guard let command = args.first else {
            usage(stderr: stderr)
            return exitUsage
        }
        let rest = Array(args.dropFirst())
        switch command {
        case "add":
            return add(arguments: rest, store: store, now: now, stdout: stdout, stderr: stderr)
        case "done":
            return done(arguments: rest, store: store, now: now, stdout: stdout, stderr: stderr)
        case "defer":
            return deferProject(arguments: rest, store: store, now: now, stdout: stdout, stderr: stderr)
        case "list":
            list(store: store, now: now, stdout: stdout)
            return exitOK
        case "gate":
            gate(store: store, now: now, stdout: stdout)
            return exitOK
        case "help", "--help", "-h":
            help(stdout: stdout)
            return exitOK
        default:
            usage(stderr: stderr)
            return exitUsage
        }
    }

    // MARK: - Commands

    /// `codenotch project add "Title"` — opens a project, or refuses with
    /// exit 1 (naming what must be completed first) while the gate is full.
    static func add(arguments: [String], store: ProjectStore, now: Date,
                    stdout: (String) -> Void, stderr: (String) -> Void) -> Int32 {
        guard let titleArg = arguments.first else {
            usage(stderr: stderr)
            return exitUsage
        }
        let title = titleArg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            stderr("error: project title must not be empty")
            return exitUsage
        }
        switch store.add(title: title, now: now) {
        case .success:
            let state = store.gateState(now: now)
            guard let project = store.resolve(title) else {
                stdout("added \"\(title)\" (\(state.active)/\(state.cap) active)")
                return exitOK
            }
            stdout("added \(project.id.uuidString) \"\(project.title)\" (\(state.active)/\(state.cap) active)")
            return exitOK
        case .failure(.capReached):
            let state = store.gateState(now: now)
            let open = store.list()
                .filter { $0.status == .active }
                .map { "\"\($0.title)\"" }
            let names = open.isEmpty ? "an active project" : open.joined(separator: ", ")
            stderr("project gate is full (\(state.active)/\(state.cap) active); complete or defer \(names) first")
            return exitFailure
        case .failure:
            stderr("error: could not add project")
            return exitFailure
        }
    }

    /// `codenotch project done <id-or-title>` — completes a project.
    static func done(arguments: [String], store: ProjectStore, now: Date,
                     stdout: (String) -> Void, stderr: (String) -> Void) -> Int32 {
        guard let identifier = arguments.first else {
            usage(stderr: stderr)
            return exitUsage
        }
        guard let project = store.resolve(identifier) else {
            stderr("no project matching \"\(identifier)\"")
            return exitFailure
        }
        guard case .success = store.complete(id: project.id, now: now) else {
            stderr("error: could not complete \"\(project.title)\"")
            return exitFailure
        }
        let state = store.gateState(now: now)
        stdout("completed \(project.id.uuidString) \"\(project.title)\" (\(state.active)/\(state.cap) active)")
        return exitOK
    }

    /// `codenotch project defer <id-or-title> --until YYYY-MM-DD` — parks a
    /// project, freeing its slot. The date must be in the future.
    static func deferProject(arguments: [String], store: ProjectStore, now: Date,
                             stdout: (String) -> Void, stderr: (String) -> Void) -> Int32 {
        guard arguments.count == 3, arguments[1] == "--until" else {
            usage(stderr: stderr)
            return exitUsage
        }
        let identifier = arguments[0]
        guard let project = store.resolve(identifier) else {
            stderr("no project matching \"\(identifier)\"")
            return exitFailure
        }
        guard let until = parseDay(arguments[2]) else {
            stderr("invalid defer date \"\(arguments[2])\" — use YYYY-MM-DD")
            return exitFailure
        }
        switch store.defer(id: project.id, until: until, now: now) {
        case .success:
            stdout("deferred \(project.id.uuidString) \"\(project.title)\" until \(dayString(until)) (slot freed)")
            return exitOK
        case .failure(.invalidDate):
            stderr("defer date must be in the future — \"\(arguments[2])\" is not")
            return exitFailure
        case .failure:
            stderr("error: could not defer \"\(project.title)\"")
            return exitFailure
        }
    }

    /// `codenotch project list` — every project, grouped by status.
    static func list(store: ProjectStore, now: Date, stdout: (String) -> Void) {
        let state = store.gateState(now: now)
        stdout("Project Gate: \(state.active)/\(state.cap) active, "
            + "\(state.deferred) deferred, \(state.completed) completed")

        func section(_ title: String, _ projects: [Project]) {
            stdout(title)
            for (index, project) in projects.enumerated() {
                stdout("  \(index + 1). \(project.id.uuidString)  \(project.title)\(detail(for: project, now: now))")
            }
        }
        let all = store.list()
        section("Active:", all.filter { $0.status == .active })
        section("Deferred:", all.filter { $0.status == .deferred })
        section("Completed:", all.filter { $0.status == .completed })
    }

    /// `codenotch project gate` — the cap state on one line, for agents that
    /// parse rather than read.
    static func gate(store: ProjectStore, now: Date, stdout: (String) -> Void) {
        let state = store.gateState(now: now)
        stdout("cap=\(state.cap) active=\(state.active)/\(state.cap) "
            + "deferred=\(state.deferred) completed=\(state.completed) slots_left=\(state.slotsLeft)")
    }

    // MARK: - Help

    static func usage(stderr: (String) -> Void) {
        stderr("usage: codenotch project <add|done|defer|list|gate|help>")
        stderr("  add \"Title\"                    open a project (fails at the cap)")
        stderr("  done <id-or-title>              complete a project")
        stderr("  defer <id-or-title> --until YYYY-MM-DD   park a project until a date")
        stderr("  list                            show every project")
        stderr("  gate                            print the cap state (for scripts)")
    }

    static func help(stdout: (String) -> Void) {
        stdout("codenotch project — the WIP gate (cap \(ProjectStore.cap))")
        usage(stderr: stdout)
    }

    // MARK: - Dates

    /// `YYYY-MM-DD` in the local calendar, starting at midnight local time.
    static func parseDay(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Rendering

    /// The status line a list row carries: age for active projects, the due
    /// date for deferred ones, the completion date for finished ones.
    static func detail(for project: Project, now: Date) -> String {
        switch project.status {
        case .active:
            let days = Int(max(0, now.timeIntervalSince(project.createdAt)) / 86_400)
            return "  ·  \(days == 0 ? "new" : "\(days)d")"
        case .deferred:
            guard let until = project.deferUntil else { return "  ·  deferred" }
            return "  ·  until \(dayString(until))"
        case .completed:
            guard let done = project.completedAt else { return "  ·  done" }
            return "  ·  done \(dayString(done))"
        }
    }

    private static func writeStderr(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}
