import SwiftUI

@main
struct InternetSpeedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var launchAtLoginManager: LaunchAtLoginManager?
    private var lifecycleMonitor: AppLifecycleMonitor?
    private let logger = BufferedAppLogger()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runner = SpeedTestRunner(logger: logger)
        let viewModel = MenuBarViewModel(runner: runner, logger: logger)
        let launchAtLoginManager = LaunchAtLoginManager(logger: logger)
        self.launchAtLoginManager = launchAtLoginManager
        statusBarController = StatusBarController(
            viewModel: viewModel,
            launchAtLoginManager: launchAtLoginManager,
            logger: logger
        )
        lifecycleMonitor = AppLifecycleMonitor(logger: logger) {
            viewModel.handleWakeOrClockChange()
        }
        logger.log(.info, category: .appLifecycle, "Application finished launching.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.log(.info, category: .appLifecycle, "Application will terminate.")
    }
}
