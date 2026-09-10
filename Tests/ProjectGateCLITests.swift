import XCTest
@testable import Codenotch

final class ProjectGateCLITests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_900_000)
    private let day: TimeInterval = 86_400

    private func makeStore(_ name: String = "ProjectGateCLITests.\(UUID().uuidString)") -> ProjectStore {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return ProjectStore(defaults: defaults)
    }

    /// A harness that captures stdout/stderr instead of printing. A class so
    /// the escaping closures mutate the one shared instance.
    private final class Capture {
        var out: [String] = []
        var err: [String] = []
        var stdout: (String) -> Void { { [weak self] in self?.out.append($0) } }
        var stderr: (String) -> Void { { [weak self] in self?.err.append($0) } }
    }

    // MARK: - Add

    func testAddPrintsIdAndCount() {
        let store = makeStore()
        var capture = Capture()
        let code = ProjectGateCLI.run(arguments: ["project", "add", "Whale Watching"],
                                      store: store, now: now,
                                      stdout: capture.stdout, stderr: capture.stderr)
        XCTAssertEqual(code, 0)
        XCTAssertEqual(capture.err, [])
        XCTAssertTrue(capture.out.first?.contains("Whale Watching") == true)
        XCTAssertTrue(capture.out.first?.contains("1/5") == true)
    }

    func testAddAtCapFailsWithExitOneAndNamesOpenProjects() {
        let store = makeStore()
        for index in 1...5 {
            XCTAssertSuccess(store.add(title: "P\(index)", now: now))
        }
        var capture = Capture()
        let code = ProjectGateCLI.run(arguments: ["project", "add", "Sixth"],
                                      store: store, now: now,
                                      stdout: capture.stdout, stderr: capture.stderr)
        XCTAssertEqual(code, 1)
        XCTAssertTrue(capture.err.joined().contains("full"))
        XCTAssertTrue(capture.err.joined().contains("P1"))
    }

    func testAddRequiresTitle() {
        let store = makeStore()
        var capture = Capture()
        let code = ProjectGateCLI.run(arguments: ["project", "add"],
                                      store: store, now: now,
                                      stdout: capture.stdout, stderr: capture.stderr)
        XCTAssertEqual(code, 2)
    }

    // MARK: - Done

    func testDoneCompletesAndFreesSlot() {
        let store = makeStore()
        XCTAssertSuccess(store.add(title: "Alpha", now: now))
        var capture = Capture()
        let code = ProjectGateCLI.run(arguments: ["project", "done", "alpha"],
                                      store: store, now: now,
                                      stdout: capture.stdout, stderr: capture.stderr)
        XCTAssertEqual(code, 0)
        XCTAssertEqual(store.gateState(now: now).active, 0)
        XCTAssertEqual(store.gateState(now: now).completed, 1)
    }

    func testDoneUnknownFails() {
        let store = makeStore()
        var capture = Capture()
        let code = ProjectGateCLI.run(arguments: ["project", "done", "nope"],
                                      store: store, now: now,
                                      stdout: capture.stdout, stderr: capture.stderr)
        XCTAssertEqual(code, 1)
        XCTAssertTrue(capture.err.joined().contains("no project matching"))
    }

    // MARK: - Defer

    func testDeferFreesSlotAndRejectsPastDate() {
        let store = makeStore()
        XCTAssertSuccess(store.add(title: "Alpha", now: now))
        var capture = Capture()
        let future = dayString(now.addingTimeInterval(day))
        let ok = ProjectGateCLI.run(arguments: ["project", "defer", "alpha", "--until", future],
                                    store: store, now: now,
                                    stdout: capture.stdout, stderr: capture.stderr)
        XCTAssertEqual(ok, 0)
        XCTAssertEqual(store.gateState(now: now).deferred, 1)
        XCTAssertEqual(store.gateState(now: now).active, 0)

        var capture2 = Capture()
        let past = dayString(now.addingTimeInterval(-day))
        let bad = ProjectGateCLI.run(arguments: ["project", "defer", "alpha", "--until", past],
                                     store: store, now: now,
                                     stdout: capture2.stdout, stderr: capture2.stderr)
        XCTAssertEqual(bad, 1)
    }

    // MARK: - List & gate

    func testGatePrintsParsableLine() {
        let store = makeStore()
        XCTAssertSuccess(store.add(title: "Alpha", now: now))
        var capture = Capture()
        let code = ProjectGateCLI.run(arguments: ["project", "gate"],
                                      store: store, now: now,
                                      stdout: capture.stdout, stderr: capture.stderr)
        XCTAssertEqual(code, 0)
        let line = capture.out.first ?? ""
        XCTAssertTrue(line.contains("cap=5"))
        XCTAssertTrue(line.contains("active=1/5"))
        XCTAssertTrue(line.contains("slots_left=4"))
    }

    func testListShowsSections() {
        let store = makeStore()
        XCTAssertSuccess(store.add(title: "Alpha", now: now))
        var capture = Capture()
        let code = ProjectGateCLI.run(arguments: ["project", "list"],
                                      store: store, now: now,
                                      stdout: capture.stdout, stderr: capture.stderr)
        XCTAssertEqual(code, 0)
        let joined = capture.out.joined(separator: "\n")
        XCTAssertTrue(joined.contains("Active:"))
        XCTAssertTrue(joined.contains("Deferred:"))
        XCTAssertTrue(joined.contains("Completed:"))
        XCTAssertTrue(joined.contains("Alpha"))
    }

    // MARK: - Unknown command

    func testUnknownCommandIsUsageError() {
        let store = makeStore()
        var capture = Capture()
        let code = ProjectGateCLI.run(arguments: ["project", "frobnicate"],
                                      store: store, now: now,
                                      stdout: capture.stdout, stderr: capture.stderr)
        XCTAssertEqual(code, 2)
    }

    // MARK: - Helpers

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func XCTAssertSuccess(_ result: Result<Void, ProjectGateError>,
                                  file: StaticString = #filePath, line: UInt = #line) {
        guard case .success = result else {
            XCTFail("expected success, got \(result)", file: file, line: line)
            return
        }
    }
}
