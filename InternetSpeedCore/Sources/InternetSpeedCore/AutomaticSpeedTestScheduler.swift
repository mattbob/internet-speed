import Foundation

@MainActor
protocol AutomaticSpeedTestScheduling: AnyObject {
    var nextRunDate: Date? { get }
    var onNextRunDateChange: ((Date?) -> Void)? { get set }

    func start(runDue: @escaping @MainActor () async -> Void)
    func updateSchedule(anchorDate: Date?, interval: AutoTestInterval)
    func handleWakeOrClockChange()
    func stop()
}

@MainActor
final class AutomaticSpeedTestScheduler: AutomaticSpeedTestScheduling {
    typealias SleepClosure = @Sendable (Duration) async throws -> Void

    var onNextRunDateChange: ((Date?) -> Void)?

    private(set) var nextRunDate: Date? {
        didSet {
            onNextRunDateChange?(nextRunDate)
        }
    }

    private let now: @Sendable () -> Date
    private let sleep: SleepClosure
    private let logger: any AppLogging
    private var anchorDate: Date?
    private var interval: AutoTestInterval = .fourHours
    private var runDue: (@MainActor () async -> Void)?
    private var scheduledTask: Task<Void, Never>?
    private var isStarted = false
    private var generation = 0

    init(
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping SleepClosure = { duration in
            try await Task.sleep(for: duration)
        },
        logger: any AppLogging = NoOpAppLogger()
    ) {
        self.now = now
        self.sleep = sleep
        self.logger = logger
    }

    deinit {
        scheduledTask?.cancel()
    }

    func start(runDue: @escaping @MainActor () async -> Void) {
        self.runDue = runDue
        isStarted = true
        logger.log(.info, category: .scheduler, "Automatic scheduler started.")
        reschedule()
    }

    func updateSchedule(anchorDate: Date?, interval: AutoTestInterval) {
        self.anchorDate = anchorDate
        self.interval = interval
        logger.log(
            .debug,
            category: .scheduler,
            "Updating schedule. interval=\(interval.rawValue) anchor=\(anchorDate?.formatted(date: .abbreviated, time: .standard) ?? "none")"
        )
        reschedule()
    }

    func handleWakeOrClockChange() {
        logger.log(.info, category: .scheduler, "Received wake or clock-change event.")
        reschedule()
    }

    func stop() {
        logger.log(.info, category: .scheduler, "Automatic scheduler stopped.")
        isStarted = false
        scheduledTask?.cancel()
        scheduledTask = nil
    }

    private func reschedule() {
        scheduledTask?.cancel()
        scheduledTask = nil

        let next = Self.calculateNextRunDate(anchorDate: anchorDate, interval: interval, now: now())
        nextRunDate = next

        guard isStarted, let next else {
            return
        }

        generation += 1
        let currentGeneration = generation
        let delay = max(0, next.timeIntervalSince(now()))

        if delay <= 0 {
            logger.log(.info, category: .scheduler, "Automatic test is due immediately.")
        } else {
            logger.log(
                .debug,
                category: .scheduler,
                "Next automatic test scheduled in \(Int(delay.rounded())) seconds."
            )
        }

        scheduledTask = Task { [weak self] in
            guard let self else {
                return
            }

            if delay > 0 {
                do {
                    try await sleep(Self.duration(for: delay))
                } catch {
                    return
                }
            }

            await fireIfCurrent(generation: currentGeneration)
        }
    }

    private func fireIfCurrent(generation: Int) async {
        guard isStarted, generation == self.generation else {
            return
        }

        logger.log(.info, category: .scheduler, "Automatic test is starting now.")
        await runDue?()
    }

    private static func duration(for interval: TimeInterval) -> Duration {
        .nanoseconds(Int64(interval * 1_000_000_000))
    }

    static func calculateNextRunDate(
        anchorDate: Date?,
        interval: AutoTestInterval,
        now: Date
    ) -> Date? {
        guard let intervalSeconds = interval.interval else {
            return nil
        }

        guard let anchorDate else {
            return now
        }

        return max(anchorDate.addingTimeInterval(intervalSeconds), now)
    }
}
