import AppKit
import Foundation

@MainActor
final class DiagnosticsController {
    private let viewModel: MenuBarViewModel
    private let launchAtLoginManager: LaunchAtLoginManager
    private let logger: BufferedAppLogger
    private let pasteboard: NSPasteboard

    init(
        viewModel: MenuBarViewModel,
        launchAtLoginManager: LaunchAtLoginManager,
        logger: BufferedAppLogger,
        pasteboard: NSPasteboard = .general
    ) {
        self.viewModel = viewModel
        self.launchAtLoginManager = launchAtLoginManager
        self.logger = logger
        self.pasteboard = pasteboard
    }

    func copyReport() {
        let report = buildReport()
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
        logger.log(.info, category: .diagnostics, "Copied diagnostics report to the pasteboard.")
    }

    private func buildReport() -> String {
        let bundle = Bundle.main
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let lastResultSummary: String

        if let lastResult = viewModel.lastResult {
            lastResultSummary = "\(lastResult.measuredAtDisplayString) | down \(lastResult.downloadDisplayString) | up \(lastResult.uploadDisplayString)"
        } else {
            lastResultSummary = "none"
        }

        let nextRunSummary = viewModel.nextAutomaticRunDisplayString ?? "none"
        let anchorSummary = viewModel.diagnosticsScheduleAnchor?.formatted(date: .abbreviated, time: .shortened) ?? "none"
        let historySummary = viewModel.speedHistory.suffix(5).map {
            "\($0.measuredAtDisplayString) | down \($0.downloadDisplayString) | up \($0.uploadDisplayString)"
        }
        let logSummary = logger.recentEntries(limit: 25).map {
            "\($0.timestamp.formatted(date: .omitted, time: .standard)) [\($0.level.rawValue)] \($0.category.rawValue): \($0.message)"
        }

        return [
            "Internet Speed Diagnostics",
            "Generated: \(Date().formatted(date: .abbreviated, time: .standard))",
            "App version: \(shortVersion) (\(buildNumber))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "networkQuality available: \(FileManager.default.isExecutableFile(atPath: "/usr/bin/networkQuality") ? "yes" : "no")",
            "State: \(viewModel.diagnosticsStateDescription)",
            "Auto interval: \(viewModel.autoTestInterval.title)",
            "Next automatic run: \(nextRunSummary)",
            "Schedule anchor: \(anchorSummary)",
            "Launch at login: \(launchAtLoginManager.statusDescription)",
            "Last result: \(lastResultSummary)",
            "History entries retained: \(viewModel.speedHistory.count)",
            "",
            "Recent results:",
            historySummary.isEmpty ? "- none" : historySummary.map { "- \($0)" }.joined(separator: "\n"),
            "",
            "Recent logs:",
            logSummary.isEmpty ? "- none" : logSummary.map { "- \($0)" }.joined(separator: "\n"),
        ].joined(separator: "\n")
    }
}
