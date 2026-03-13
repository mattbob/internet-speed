import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var errorMessage: String?

    private let appService: SMAppService
    private let userDefaults: UserDefaults
    private let configuredKey: String
    private let logger: any AppLogging

    init(
        appService: SMAppService = .mainApp,
        userDefaults: UserDefaults = .standard,
        configuredKey: String = "launchAtLoginConfigured",
        logger: any AppLogging = NoOpAppLogger()
    ) {
        self.appService = appService
        self.userDefaults = userDefaults
        self.configuredKey = configuredKey
        self.logger = logger
        self.isEnabled = appService.status == .enabled

        refreshStatus()
        configureDefaultIfNeeded()
    }

    var statusDescription: String {
        switch appService.status {
        case .enabled:
            return "enabled"
        case .requiresApproval:
            return "requires approval"
        case .notFound:
            return "not found"
        case .notRegistered:
            return "not registered"
        @unknown default:
            return "unknown"
        }
    }

    func updateIsEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try appService.register()
            } else {
                try appService.unregister()
            }

            userDefaults.set(true, forKey: configuredKey)
            errorMessage = nil
            logger.log(.info, category: .launchAtLogin, "Launch at login set to \(enabled).")
        } catch {
            errorMessage = error.localizedDescription
            logger.log(.error, category: .launchAtLogin, "Failed to update launch at login: \(error.localizedDescription)")
        }

        refreshStatus()
    }

    private func configureDefaultIfNeeded() {
        guard !userDefaults.bool(forKey: configuredKey) else {
            return
        }

        updateIsEnabled(true)
    }

    private func refreshStatus() {
        switch appService.status {
        case .enabled:
            isEnabled = true
            errorMessage = nil
        case .requiresApproval:
            isEnabled = false
            errorMessage = "Open System Settings > General > Login Items to finish enabling launch at login."
            logger.log(.info, category: .launchAtLogin, "Launch at login requires user approval.")
        case .notFound, .notRegistered:
            isEnabled = false
            errorMessage = nil
        @unknown default:
            isEnabled = false
            errorMessage = "Launch at login is unavailable on this macOS version."
            logger.log(.error, category: .launchAtLogin, "Launch at login returned an unknown status.")
        }
    }
}
