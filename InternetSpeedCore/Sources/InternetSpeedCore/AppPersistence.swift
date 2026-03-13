import Foundation

struct PersistedAppStateSnapshot: Equatable, Sendable {
    let lastResult: SpeedTestResult?
    let speedHistory: [SpeedTestResult]
    let autoTestInterval: AutoTestInterval
    let lastScheduleAnchorDate: Date?
}

protocol AppStatePersisting: Sendable {
    func load() -> PersistedAppStateSnapshot
    func save(_ snapshot: PersistedAppStateSnapshot)
}

final class UserDefaultsAppStateStore: AppStatePersisting, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let snapshotKey: String
    private let legacyResultKey: String
    private let legacyHistoryKey: String
    private let legacyAutoTestIntervalKey: String
    private let logger: any AppLogging

    init(
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "appStateSnapshot",
        legacyResultKey: String = "lastSpeedTestResult",
        legacyHistoryKey: String = "speedTestHistory",
        legacyAutoTestIntervalKey: String = "autoTestInterval",
        logger: any AppLogging = NoOpAppLogger()
    ) {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
        self.legacyResultKey = legacyResultKey
        self.legacyHistoryKey = legacyHistoryKey
        self.legacyAutoTestIntervalKey = legacyAutoTestIntervalKey
        self.logger = logger
    }

    func load() -> PersistedAppStateSnapshot {
        if let data = userDefaults.data(forKey: snapshotKey),
           let envelope = try? JSONDecoder().decode(PersistedAppStateEnvelope.self, from: data) {
            logger.log(.debug, category: .persistence, "Loaded persisted snapshot v\(envelope.version).")
            return PersistedAppStateSnapshot(
                lastResult: envelope.lastResult,
                speedHistory: envelope.speedHistory,
                autoTestInterval: AutoTestInterval(rawValue: envelope.autoTestIntervalRawValue) ?? .fourHours,
                lastScheduleAnchorDate: envelope.lastScheduleAnchorDate
            )
        }

        logger.log(.info, category: .persistence, "No snapshot found. Attempting legacy migration.")
        let lastResult = Self.loadLegacyResult(from: userDefaults, key: legacyResultKey)
        let speedHistory = Self.loadLegacyHistory(from: userDefaults, key: legacyHistoryKey)
        let interval = Self.loadLegacyInterval(from: userDefaults, key: legacyAutoTestIntervalKey)

        return PersistedAppStateSnapshot(
            lastResult: lastResult,
            speedHistory: speedHistory,
            autoTestInterval: interval,
            lastScheduleAnchorDate: lastResult?.measuredAt
        )
    }

    func save(_ snapshot: PersistedAppStateSnapshot) {
        let envelope = PersistedAppStateEnvelope(
            version: PersistedAppStateEnvelope.currentVersion,
            lastResult: snapshot.lastResult,
            speedHistory: snapshot.speedHistory,
            autoTestIntervalRawValue: snapshot.autoTestInterval.rawValue,
            lastScheduleAnchorDate: snapshot.lastScheduleAnchorDate
        )

        do {
            let data = try JSONEncoder().encode(envelope)
            userDefaults.set(data, forKey: snapshotKey)
        } catch {
            assertionFailure("Failed to encode persisted app state: \(error)")
        }

        if let lastResult = snapshot.lastResult {
            userDefaults.set(try? JSONEncoder().encode(lastResult), forKey: legacyResultKey)
        } else {
            userDefaults.removeObject(forKey: legacyResultKey)
        }

        userDefaults.set(try? JSONEncoder().encode(snapshot.speedHistory), forKey: legacyHistoryKey)
        userDefaults.set(snapshot.autoTestInterval.rawValue, forKey: legacyAutoTestIntervalKey)
    }

    private static func loadLegacyResult(from userDefaults: UserDefaults, key: String) -> SpeedTestResult? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(SpeedTestResult.self, from: data)
    }

    private static func loadLegacyHistory(from userDefaults: UserDefaults, key: String) -> [SpeedTestResult] {
        guard let data = userDefaults.data(forKey: key) else {
            return []
        }

        return (try? JSONDecoder().decode([SpeedTestResult].self, from: data)) ?? []
    }

    private static func loadLegacyInterval(from userDefaults: UserDefaults, key: String) -> AutoTestInterval {
        guard
            let rawValue = userDefaults.string(forKey: key),
            let interval = AutoTestInterval(rawValue: rawValue)
        else {
            return .fourHours
        }

        return interval
    }
}

private struct PersistedAppStateEnvelope: Codable {
    static let currentVersion = 1

    let version: Int
    let lastResult: SpeedTestResult?
    let speedHistory: [SpeedTestResult]
    let autoTestIntervalRawValue: String
    let lastScheduleAnchorDate: Date?
}
