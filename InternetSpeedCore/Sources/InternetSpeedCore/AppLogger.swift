import Foundation
import OSLog

enum AppLogLevel: String, Codable, Sendable {
    case debug
    case info
    case error
}

enum AppLogCategory: String, Codable, Sendable {
    case appLifecycle = "app_lifecycle"
    case diagnostics
    case launchAtLogin = "launch_at_login"
    case persistence
    case scheduler
    case speedTest = "speed_test"
}

struct AppLogEntry: Codable, Equatable, Identifiable, Sendable {
    let timestamp: Date
    let level: AppLogLevel
    let category: AppLogCategory
    let message: String

    var id: String {
        "\(timestamp.timeIntervalSince1970)-\(category.rawValue)-\(message)"
    }
}

protocol AppLogging: Sendable {
    func log(_ level: AppLogLevel, category: AppLogCategory, _ message: String)
}

struct NoOpAppLogger: AppLogging {
    func log(_ level: AppLogLevel, category: AppLogCategory, _ message: String) {}
}

final class BufferedAppLogger: AppLogging, @unchecked Sendable {
    private let subsystem: String
    private let maxEntries: Int
    private let accessQueue = DispatchQueue(label: "com.mattbob.InternetSpeed.logger")
    private var entries: [AppLogEntry] = []

    init(subsystem: String = "com.mattbob.InternetSpeed", maxEntries: Int = 200) {
        self.subsystem = subsystem
        self.maxEntries = maxEntries
    }

    func log(_ level: AppLogLevel, category: AppLogCategory, _ message: String) {
        let entry = AppLogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message
        )

        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }

        accessQueue.sync {
            entries.append(entry)
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }
        }
    }

    func recentEntries(limit: Int? = nil) -> [AppLogEntry] {
        accessQueue.sync {
            guard let limit else {
                return entries
            }

            return Array(entries.suffix(limit))
        }
    }
}
