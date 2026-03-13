import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let contextMenu = NSMenu()
    private let intervalMenu = NSMenu()
    private let viewModel: MenuBarViewModel
    private let launchAtLoginManager: LaunchAtLoginManager
    private let diagnosticsController: DiagnosticsController
    private let intervalMenuItem = NSMenuItem()
    private let launchAtLoginMenuItem = NSMenuItem()
    private let diagnosticsMenuItem = NSMenuItem()
    private var cancellables = Set<AnyCancellable>()

    init(
        viewModel: MenuBarViewModel,
        launchAtLoginManager: LaunchAtLoginManager,
        logger: BufferedAppLogger
    ) {
        self.viewModel = viewModel
        self.launchAtLoginManager = launchAtLoginManager
        self.diagnosticsController = DiagnosticsController(
            viewModel: viewModel,
            launchAtLoginManager: launchAtLoginManager,
            logger: logger
        )
        super.init()
        configurePopover()
        configureMenu()
        configureStatusItem()
        bindViewModel()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 360)
        popover.contentViewController = makePopoverContentViewController()
    }

    private func configureMenu() {
        intervalMenuItem.title = "Interval"
        intervalMenuItem.submenu = intervalMenu
        contextMenu.addItem(intervalMenuItem)

        for interval in AutoTestInterval.allCases {
            let item = NSMenuItem(
                title: interval.title,
                action: #selector(selectInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = interval.rawValue
            intervalMenu.addItem(item)
        }

        contextMenu.addItem(.separator())

        diagnosticsMenuItem.title = "Copy Diagnostics"
        diagnosticsMenuItem.target = self
        diagnosticsMenuItem.action = #selector(copyDiagnostics)
        contextMenu.addItem(diagnosticsMenuItem)
        contextMenu.addItem(.separator())

        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.action = #selector(toggleLaunchAtLogin)
        contextMenu.addItem(launchAtLoginMenuItem)
        contextMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        contextMenu.addItem(quitItem)

        updateContextMenu()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Internet Speed"
        updateStatusItemImage()
    }

    private func bindViewModel() {
        Publishers.CombineLatest3(
            viewModel.$state,
            viewModel.$lastResult,
            launchAtLoginManager.$isEnabled
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.updateStatusItemImage()
                self?.updateContextMenu()
            }
            .store(in: &cancellables)
    }

    private func updateStatusItemImage() {
        guard let button = statusItem.button else {
            return
        }

        let image = NSImage(
            systemSymbolName: viewModel.statusItemSymbol,
            accessibilityDescription: "Internet Speed"
        )
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        button.image = image
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let currentEvent = NSApp.currentEvent else {
            togglePopover(relativeTo: sender)
            return
        }

        switch currentEvent.type {
        case .rightMouseUp:
            showContextMenu()
        case .leftMouseUp:
            togglePopover(relativeTo: sender)
        default:
            break
        }
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.contentViewController = makePopoverContentViewController()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        popover.performClose(nil)
        updateContextMenu()
        statusItem.menu = contextMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func updateContextMenu() {
        for item in intervalMenu.items {
            guard
                let rawValue = item.representedObject as? String,
                let interval = AutoTestInterval(rawValue: rawValue)
            else {
                item.state = .off
                continue
            }

            item.state = interval == viewModel.autoTestInterval ? .on : .off
        }

        launchAtLoginMenuItem.title = "Open on Login"
        launchAtLoginMenuItem.state = launchAtLoginManager.isEnabled ? .on : .off
    }

    @objc
    private func selectInterval(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let interval = AutoTestInterval(rawValue: rawValue)
        else {
            return
        }

        viewModel.updateAutoTestInterval(interval)
        updateContextMenu()
    }

    @objc
    private func toggleLaunchAtLogin() {
        launchAtLoginManager.updateIsEnabled(!launchAtLoginManager.isEnabled)
        updateContextMenu()
    }

    @objc
    private func copyDiagnostics() {
        diagnosticsController.copyReport()
    }

    @objc
    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func makePopoverContentViewController() -> NSHostingController<MenuBarView> {
        NSHostingController(rootView: MenuBarView(viewModel: viewModel))
    }
}
