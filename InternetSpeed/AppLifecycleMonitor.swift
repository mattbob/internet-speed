import AppKit
import Foundation

@MainActor
final class AppLifecycleMonitor {
    private let logger: any AppLogging
    private let onWakeOrClockChange: @MainActor () -> Void
    private let workspaceNotificationCenter: NotificationCenter
    private let distributedNotificationCenter: DistributedNotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        distributedNotificationCenter: DistributedNotificationCenter = .default(),
        logger: any AppLogging = NoOpAppLogger(),
        onWakeOrClockChange: @escaping @MainActor () -> Void
    ) {
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.distributedNotificationCenter = distributedNotificationCenter
        self.logger = logger
        self.onWakeOrClockChange = onWakeOrClockChange
        startObserving()
    }

    deinit {
        for observer in observers {
            workspaceNotificationCenter.removeObserver(observer)
            distributedNotificationCenter.removeObserver(observer)
        }
    }

    private func startObserving() {
        let wakeObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }

            logger.log(.info, category: .appLifecycle, "Received wake notification.")
            Task { @MainActor in
                self.onWakeOrClockChange()
            }
        }
        observers.append(wakeObserver)

        let clockObserver = distributedNotificationCenter.addObserver(
            forName: NSNotification.Name.NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }

            logger.log(.info, category: .appLifecycle, "Received system clock change notification.")
            Task { @MainActor in
                self.onWakeOrClockChange()
            }
        }
        observers.append(clockObserver)
    }
}
