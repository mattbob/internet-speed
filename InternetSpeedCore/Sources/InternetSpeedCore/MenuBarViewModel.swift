import Combine
import Foundation

enum AutoTestInterval: String, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes
    case hourly
    case fourHours
    case twelveHours
    case daily
    case never

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .fifteenMinutes:
            return "Every 15 minutes"
        case .hourly:
            return "Every hour"
        case .fourHours:
            return "Every 4 hours"
        case .twelveHours:
            return "Every 12 hours"
        case .daily:
            return "Every day"
        case .never:
            return "Off"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .fifteenMinutes:
            return 15 * 60
        case .hourly:
            return 60 * 60
        case .fourHours:
            return 4 * 60 * 60
        case .twelveHours:
            return 12 * 60 * 60
        case .daily:
            return 24 * 60 * 60
        case .never:
            return nil
        }
    }
}

@MainActor
final class MenuBarViewModel: ObservableObject {
    static let historyRetentionInterval: TimeInterval = 12 * 60 * 60
    static let maxStoredHistoryEntries = 500

    enum State: Equatable {
        case idle
        case running
        case failure(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastResult: SpeedTestResult?
    @Published private(set) var speedHistory: [SpeedTestResult]
    @Published var autoTestInterval: AutoTestInterval {
        didSet {
            guard oldValue != autoTestInterval else {
                return
            }

            logger.log(.info, category: .scheduler, "Auto test interval changed to \(autoTestInterval.rawValue).")
            persistState()
            scheduler.updateSchedule(anchorDate: lastScheduleAnchorDate, interval: autoTestInterval)
        }
    }
    @Published private(set) var nextAutomaticRunDate: Date?

    private let runner: any SpeedTestRunning
    private let persistence: any AppStatePersisting
    private let scheduler: any AutomaticSpeedTestScheduling
    private let now: @Sendable () -> Date
    private let logger: any AppLogging
    private var lastScheduleAnchorDate: Date?

    init(
        runner: any SpeedTestRunning = SpeedTestRunner(),
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "appStateSnapshot",
        storageKey: String = "lastSpeedTestResult",
        historyStorageKey: String = "speedTestHistory",
        autoTestIntervalKey: String = "autoTestInterval",
        now: @escaping @Sendable () -> Date = { Date() },
        autoStartScheduler: Bool = true,
        scheduler: (any AutomaticSpeedTestScheduling)? = nil,
        logger: any AppLogging = NoOpAppLogger()
    ) {
        self.runner = runner
        self.persistence = UserDefaultsAppStateStore(
            userDefaults: userDefaults,
            snapshotKey: snapshotKey,
            legacyResultKey: storageKey,
            legacyHistoryKey: historyStorageKey,
            legacyAutoTestIntervalKey: autoTestIntervalKey,
            logger: logger
        )
        self.now = now
        self.logger = logger
        self.scheduler = scheduler ?? AutomaticSpeedTestScheduler(now: now, logger: logger)

        let persistedState = self.persistence.load()
        self.lastResult = persistedState.lastResult
        let trimmedHistory = Self.trimHistory(persistedState.speedHistory, now: now())
        self.speedHistory = trimmedHistory
        self.autoTestInterval = persistedState.autoTestInterval
        self.lastScheduleAnchorDate = persistedState.lastScheduleAnchorDate ?? persistedState.lastResult?.measuredAt
        self.nextAutomaticRunDate = nil
        self.scheduler.onNextRunDateChange = { [weak self] date in
            self?.nextAutomaticRunDate = date
        }
        self.scheduler.updateSchedule(anchorDate: self.lastScheduleAnchorDate, interval: self.autoTestInterval)

        if trimmedHistory != persistedState.speedHistory {
            persistState()
        }

        if autoStartScheduler {
            self.scheduler.start { [weak self] in
                guard let self else {
                    return
                }

                await self.runSpeedTest(trigger: .automatic)
            }
        }
    }

    var isRunning: Bool {
        if case .running = state {
            return true
        }

        return false
    }

    var errorMessage: String? {
        if case let .failure(message) = state {
            return message
        }

        return nil
    }

    var primaryButtonTitle: String {
        lastResult == nil ? "Run Speed Test" : "Run Again"
    }

    var headerStatusText: String {
        if isRunning {
            return "Running a fresh measurement..."
        }

        if let lastResult {
            return "Latest result from \(lastResult.measuredAtDisplayString)"
        }

        return "No measurement yet"
    }

    var statusItemSymbol: String {
        "arrow.left.arrow.right"
    }

    var automaticTestingStatusText: String {
        automaticTestingStatusText(relativeTo: now())
    }

    var nextAutomaticRunDisplayString: String? {
        guard let nextAutomaticRunDate else {
            return nil
        }

        return nextAutomaticRunDate.formatted(date: .abbreviated, time: .shortened)
    }

    var hasEnoughChartData: Bool {
        speedHistory.count >= 2
    }

    var diagnosticsStateDescription: String {
        switch state {
        case .idle:
            return "idle"
        case .running:
            return "running"
        case let .failure(message):
            return "failure: \(message)"
        }
    }

    var diagnosticsScheduleAnchor: Date? {
        lastScheduleAnchorDate
    }

    var chartAccessibilitySummary: String {
        guard let lastResult else {
            return "No recent speed history."
        }

        return "Speed history for the last 12 hours. Latest download \(lastResult.downloadDisplayString), latest upload \(lastResult.uploadDisplayString)."
    }

    func automaticTestingStatusText(relativeTo referenceDate: Date) -> String {
        guard autoTestInterval != .never else {
            return "Automatic tests are off"
        }

        guard let nextAutomaticRunDate else {
            return "Automatic tests run in the background"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: nextAutomaticRunDate, relativeTo: referenceDate)
        return "Next automatic test \(relative)"
    }

    func runSpeedTest() async {
        await runSpeedTest(trigger: .manual)
    }

    func updateAutoTestInterval(_ interval: AutoTestInterval) {
        autoTestInterval = interval
    }

    func handleWakeOrClockChange() {
        scheduler.handleWakeOrClockChange()
    }

    private func runSpeedTest(trigger: SpeedTestTrigger) async {
        guard !isRunning else {
            logger.log(.debug, category: .speedTest, "Ignoring \(trigger.rawValue) run because a test is already in progress.")
            return
        }

        logger.log(.info, category: .speedTest, "Starting \(trigger.rawValue) speed test.")
        state = .running

        do {
            let result = try await runner.run()
            lastResult = result
            appendToHistory(result)
            lastScheduleAnchorDate = result.measuredAt
            persistState()
            state = .idle
        } catch let error as LocalizedError {
            lastScheduleAnchorDate = now()
            persistState()
            let message = error.errorDescription ?? "The speed test failed."
            state = .failure(message)
            logger.log(.error, category: .speedTest, message)
        } catch {
            lastScheduleAnchorDate = now()
            persistState()
            state = .failure(error.localizedDescription)
            logger.log(.error, category: .speedTest, error.localizedDescription)
        }

        scheduler.updateSchedule(anchorDate: lastScheduleAnchorDate, interval: autoTestInterval)
    }

    private func persistState() {
        persistence.save(
            PersistedAppStateSnapshot(
                lastResult: lastResult,
                speedHistory: speedHistory,
                autoTestInterval: autoTestInterval,
                lastScheduleAnchorDate: lastScheduleAnchorDate
            )
        )
    }

    private func appendToHistory(_ result: SpeedTestResult) {
        speedHistory = Self.trimHistory(speedHistory + [result], now: now())
    }

    private static func trimHistory(_ history: [SpeedTestResult], now: Date) -> [SpeedTestResult] {
        let cutoffDate = now.addingTimeInterval(-historyRetentionInterval)

        return history
            .filter { $0.measuredAt >= cutoffDate }
            .sorted { $0.measuredAt < $1.measuredAt }
            .suffix(maxStoredHistoryEntries)
            .map(\.self)
    }
}

private enum SpeedTestTrigger {
    case manual
    case automatic

    var rawValue: String {
        switch self {
        case .manual:
            return "manual"
        case .automatic:
            return "automatic"
        }
    }
}
