import XCTest
@testable import InternetSpeedCore

@MainActor
final class MenuBarViewModelTests: XCTestCase {
    func testInitialStateLoadsPersistedResult() throws {
        let defaults = makeDefaults()
        let stored = makeResult(download: 500_000_000, upload: 300_000_000)
        let history = [
            makeResult(download: 350_000_000, upload: 120_000_000, measuredAt: stored.measuredAt.addingTimeInterval(-600)),
            stored,
        ]
        defaults.set(try JSONEncoder().encode(stored), forKey: "storedResult")
        defaults.set(try JSONEncoder().encode(history), forKey: "history")

        let viewModel = MenuBarViewModel(
            runner: ScriptedRunner(results: [.success(stored)]),
            userDefaults: defaults,
            storageKey: "storedResult",
            historyStorageKey: "history",
            now: { stored.measuredAt },
            autoStartScheduler: false
        )

        XCTAssertEqual(viewModel.lastResult, stored)
        XCTAssertEqual(viewModel.speedHistory, history)
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.autoTestInterval, .fourHours)
    }

    func testRunSpeedTestTransitionsThroughRunningStateAndPersistsResult() async throws {
        let defaults = makeDefaults()
        let expected = makeResult(download: 940_500_000, upload: 412_000_000)
        let viewModel = MenuBarViewModel(
            runner: ScriptedRunner(results: [.success(expected)], delay: .milliseconds(200)),
            userDefaults: defaults,
            storageKey: "latestResult",
            historyStorageKey: "history",
            now: { expected.measuredAt },
            autoStartScheduler: false
        )

        let task = Task {
            await viewModel.runSpeedTest()
        }

        await Task.yield()

        XCTAssertTrue(viewModel.isRunning)
        XCTAssertEqual(viewModel.state, .running)

        await task.value

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.lastResult, expected)
        XCTAssertEqual(viewModel.speedHistory, [expected])
        XCTAssertNotNil(defaults.data(forKey: "latestResult"))
        let persistedHistory = try XCTUnwrap(defaults.data(forKey: "history"))
        XCTAssertEqual(try JSONDecoder().decode([SpeedTestResult].self, from: persistedHistory), [expected])
    }

    func testFailureKeepsLastGoodResultAndShowsError() async {
        let defaults = makeDefaults()
        let stored = makeResult(download: 800_000_000, upload: 200_000_000)
        let viewModel = MenuBarViewModel(
            runner: ScriptedRunner(
                results: [
                    .success(stored),
                    .failure(.networkQualityFailed(domain: "NSURLErrorDomain", code: -1009)),
                ]
            ),
            userDefaults: defaults,
            storageKey: "latestResult",
            historyStorageKey: "history",
            now: { stored.measuredAt },
            autoStartScheduler: false
        )

        await viewModel.runSpeedTest()
        await viewModel.runSpeedTest()

        XCTAssertEqual(viewModel.lastResult, stored)
        XCTAssertEqual(viewModel.speedHistory, [stored])
        XCTAssertEqual(viewModel.state, .failure("No internet connection detected."))
        XCTAssertEqual(viewModel.errorMessage, "No internet connection detected.")
    }

    func testAutoTestIntervalPersistsWhenUpdated() {
        let defaults = makeDefaults()
        let viewModel = MenuBarViewModel(
            runner: ScriptedRunner(results: []),
            userDefaults: defaults,
            storageKey: "latestResult",
            historyStorageKey: "history",
            autoTestIntervalKey: "autoInterval",
            now: { Date(timeIntervalSince1970: 1_710_000_000) },
            autoStartScheduler: false
        )

        viewModel.updateAutoTestInterval(.hourly)

        XCTAssertEqual(defaults.string(forKey: "autoInterval"), AutoTestInterval.hourly.rawValue)
        XCTAssertEqual(viewModel.autoTestInterval, .hourly)
    }

    func testNextAutomaticRunDateUsesLastResultAndSelectedInterval() throws {
        let defaults = makeDefaults()
        let stored = makeResult(download: 500_000_000, upload: 300_000_000)
        defaults.set(try JSONEncoder().encode(stored), forKey: "storedResult")
        defaults.set(AutoTestInterval.twelveHours.rawValue, forKey: "autoInterval")

        let now = Date(timeIntervalSince1970: 1_710_000_000 + 600)
        let viewModel = MenuBarViewModel(
            runner: ScriptedRunner(results: []),
            userDefaults: defaults,
            storageKey: "storedResult",
            historyStorageKey: "history",
            autoTestIntervalKey: "autoInterval",
            now: { now },
            autoStartScheduler: false
        )

        XCTAssertEqual(viewModel.autoTestInterval, .twelveHours)
        XCTAssertEqual(
            viewModel.nextAutomaticRunDate,
            stored.measuredAt.addingTimeInterval(12 * 60 * 60)
        )
    }

    func testAutomaticSchedulerRunsImmediatelyWhenNoStoredResultExists() async {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let expected = makeResult(
            download: 940_500_000,
            upload: 412_000_000,
            measuredAt: now.addingTimeInterval(5)
        )

        let viewModel = MenuBarViewModel(
            runner: ScriptedRunner(results: [.success(expected)]),
            userDefaults: defaults,
            storageKey: "latestResult",
            historyStorageKey: "history",
            autoTestIntervalKey: "autoInterval",
            now: { now },
            autoStartScheduler: true
        )

        for _ in 0..<20 where viewModel.lastResult == nil {
            try? await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(viewModel.lastResult, expected)
        XCTAssertEqual(viewModel.speedHistory, [expected])
        XCTAssertEqual(
            viewModel.nextAutomaticRunDate,
            expected.measuredAt.addingTimeInterval(4 * 60 * 60)
        )
    }

    func testHistoryIsTrimmedToLast24HoursOnLoad() throws {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let stale = makeResult(
            download: 100_000_000,
            upload: 50_000_000,
            measuredAt: now.addingTimeInterval(-(MenuBarViewModel.historyRetentionInterval + 60))
        )
        let fresh = makeResult(
            download: 200_000_000,
            upload: 100_000_000,
            measuredAt: now.addingTimeInterval(-300)
        )
        defaults.set(try JSONEncoder().encode([stale, fresh]), forKey: "history")

        let viewModel = MenuBarViewModel(
            runner: ScriptedRunner(results: []),
            userDefaults: defaults,
            historyStorageKey: "history",
            now: { now },
            autoStartScheduler: false
        )

        XCTAssertEqual(viewModel.speedHistory, [fresh])
        let persistedHistory = try XCTUnwrap(defaults.data(forKey: "history"))
        XCTAssertEqual(try JSONDecoder().decode([SpeedTestResult].self, from: persistedHistory), [fresh])
    }

    func testHistoryRemainsChronologicalAfterRepeatedRuns() async {
        let defaults = makeDefaults()
        let base = Date(timeIntervalSince1970: 1_710_000_000)
        let first = makeResult(download: 120_000_000, upload: 40_000_000, measuredAt: base.addingTimeInterval(300))
        let second = makeResult(download: 240_000_000, upload: 80_000_000, measuredAt: base.addingTimeInterval(900))

        let viewModel = MenuBarViewModel(
            runner: ScriptedRunner(results: [.success(first), .success(second)]),
            userDefaults: defaults,
            historyStorageKey: "history",
            now: { second.measuredAt },
            autoStartScheduler: false
        )

        await viewModel.runSpeedTest()
        await viewModel.runSpeedTest()

        XCTAssertEqual(viewModel.speedHistory, [first, second])
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "InternetSpeedCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }

        return defaults
    }

    private func makeResult(download: Double, upload: Double, measuredAt: Date = Date(timeIntervalSince1970: 1_710_000_000)) -> SpeedTestResult {
        SpeedTestResult(
            downloadBitsPerSecond: download,
            uploadBitsPerSecond: upload,
            measuredAt: measuredAt
        )
    }
}

private actor ScriptedRunner: SpeedTestRunning {
    private var results: [TestOutcome]
    private let delay: Duration?

    init(results: [TestOutcome], delay: Duration? = nil) {
        self.results = results
        self.delay = delay
    }

    func run() async throws -> SpeedTestResult {
        if let delay {
            try await Task.sleep(for: delay)
        }

        guard !results.isEmpty else {
            throw SpeedTestRunnerError.invalidResponse
        }

        let next = results.removeFirst()
        switch next {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        }
    }
}

private enum TestOutcome: Sendable {
    case success(SpeedTestResult)
    case failure(SpeedTestRunnerError)
}
