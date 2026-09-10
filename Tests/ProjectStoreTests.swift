import XCTest
@testable import Codenotch

final class ProjectStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_900_000)
    private let day: TimeInterval = 86_400

    /// A fresh, isolated preferences domain so tests never touch the app's.
    private func makeStore(_ name: String = "ProjectStoreTests.\(UUID().uuidString)") -> ProjectStore {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return ProjectStore(defaults: defaults)
    }

    // MARK: - Cap enforcement

    func testCapIsFive() {
        XCTAssertEqual(ProjectStore.cap, 5)
    }

    func testSixthAddRejectedWhenAtCap() {
        let store = makeStore()
        for index in 1...5 {
            XCTAssertSuccess(store.add(title: "P\(index)", now: now))
        }
        XCTAssertEqual(store.activeCount(now: now), 5)
        XCTAssertEqual(store.add(title: "P6", now: now), .failure(.capReached))
    }

    func testCompleteFreesSlot() {
        let store = makeStore()
        for index in 1...5 { XCTAssertSuccess(store.add(title: "P\(index)", now: now)) }
        let target = store.resolve("P3")!
        XCTAssertSuccess(store.complete(id: target.id, now: now))
        XCTAssertEqual(store.activeCount(now: now), 4)
        XCTAssertSuccess(store.add(title: "P6", now: now))
        XCTAssertEqual(store.activeCount(now: now), 5)
    }

    // MARK: - Defer

    func testDeferFreesSlotImmediately() {
        let store = makeStore()
        for index in 1...5 { XCTAssertSuccess(store.add(title: "P\(index)", now: now)) }
        let target = store.resolve("P2")!
        XCTAssertSuccess(store.defer(id: target.id, until: now.addingTimeInterval(day), now: now))
        XCTAssertEqual(store.activeCount(now: now), 4)
        XCTAssertSuccess(store.add(title: "P6", now: now))
    }

    func testDeferRejectsPastDate() {
        let store = makeStore()
        XCTAssertSuccess(store.add(title: "P1", now: now))
        let target = store.resolve("P1")!
        XCTAssertEqual(store.defer(id: target.id, until: now.addingTimeInterval(-day), now: now),
                       .failure(.invalidDate))
    }

    func testExpiredDeferredReactivatesAndBlocksNewAddsUntilUnder() {
        let store = makeStore()
        for index in 1...5 { XCTAssertSuccess(store.add(title: "P\(index)", now: now)) }
        let target = store.resolve("P2")!
        XCTAssertSuccess(store.defer(id: target.id, until: now.addingTimeInterval(day), now: now))
        XCTAssertSuccess(store.add(title: "P6", now: now))  // fills the freed slot
        // The defer date passes: P2 returns to active, pushing over the cap.
        let later = now.addingTimeInterval(day + 1)
        XCTAssertEqual(store.activeCount(now: later), 6)
        XCTAssertEqual(store.add(title: "P7", now: later), .failure(.capReached))
    }

    // MARK: - Resolution & ordering

    func testResolveByIdAndTitleCaseInsensitive() {
        let store = makeStore()
        XCTAssertSuccess(store.add(title: "Whale Watching", now: now))
        let byTitle = store.resolve("whale watching")!
        let byID = store.resolve(byTitle.id.uuidString)!
        XCTAssertEqual(byID.id, byTitle.id)
        XCTAssertEqual(byTitle.title, "Whale Watching")
    }

    func testAddTrimsTitle() {
        let store = makeStore()
        XCTAssertSuccess(store.add(title: "  padded  ", now: now))
        XCTAssertEqual(store.resolve("padded")?.title, "padded")
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() {
        let name = "ProjectStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        var store = ProjectStore(defaults: defaults)
        XCTAssertSuccess(store.add(title: "One", now: now))
        XCTAssertSuccess(store.add(title: "Two", now: now))
        let second = store.resolve("Two")!
        XCTAssertSuccess(store.complete(id: second.id, now: now))

        // A brand-new store on the same domain must see the same list.
        store = ProjectStore(defaults: defaults)
        let state = store.gateState(now: now)
        XCTAssertEqual(state.active, 1)
        XCTAssertEqual(state.completed, 1)
        XCTAssertEqual(store.resolve("One")?.title, "One")
    }

    // MARK: - Gate state

    func testGateStateNumbers() {
        let store = makeStore()
        for index in 1...3 { XCTAssertSuccess(store.add(title: "P\(index)", now: now)) }
        let target = store.resolve("P1")!
        XCTAssertSuccess(store.complete(id: target.id, now: now))
        let deferred = store.resolve("P2")!
        XCTAssertSuccess(store.defer(id: deferred.id, until: now.addingTimeInterval(day), now: now))
        let state = store.gateState(now: now)
        XCTAssertEqual(state.active, 1)
        XCTAssertEqual(state.deferred, 1)
        XCTAssertEqual(state.completed, 1)
        XCTAssertEqual(state.cap, 5)
        XCTAssertEqual(state.slotsLeft, 4)
        XCTAssertFalse(state.isAtCap)
    }

    // MARK: - Helpers

    private func XCTAssertSuccess(_ result: Result<Void, ProjectGateError>,
                                  file: StaticString = #filePath, line: UInt = #line) {
        guard case .success = result else {
            XCTFail("expected success, got \(result)", file: file, line: line)
            return
        }
    }
}

extension Result where Failure == ProjectGateError, Success == Void {
    static func == (lhs: Result<Void, ProjectGateError>, rhs: Result<Void, ProjectGateError>) -> Bool {
        switch (lhs, rhs) {
        case (.success, .success): return true
        case (.failure(let a), .failure(let b)): return a == b
        default: return false
        }
    }
}
