import AppKit
import SwiftUI

@main
struct PythonUpdaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        PythonUpdateManager.shared.start()
    }

    var body: some Scene {
        WindowGroup("Python Updater") {
            UpdaterDashboard(manager: PythonUpdateManager.shared)
                .frame(minWidth: 640, minHeight: 480)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Open Python Updater")
        item.button?.target = self
        item.button?.action = #selector(openMainWindow)
        statusItem = item
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
    }
}

private struct UpdaterDashboard: View {
    @ObservedObject var manager: PythonUpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Python Updater")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("Official Python releases, checked on your schedule.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Check Now") {
                    Task { await manager.checkForUpdatesNow() }
                }
                .disabled(manager.isChecking || manager.isInstalling)
                .keyboardShortcut("r", modifiers: [.command])
            }
            .padding(28)

            Divider()

            VStack(alignment: .leading, spacing: 22) {
                GroupBox("Installed Python") {
                    LabeledContent("Version", value: manager.installedVersionText)
                    LabeledContent("Path", value: manager.pythonPath)
                        .font(.system(.body, design: .monospaced))
                }

                GroupBox("Update Status") {
                    if manager.isChecking || manager.isInstalling {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(manager.activityText)
                        }
                    } else if manager.updateAvailable {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Python \(manager.availableVersionText) is ready to install.")
                                .font(.headline)
                            HStack {
                                Button("View Release Notes") { manager.openReleasePage() }
                                Spacer()
                                Button("Install Update") {
                                    Task { await manager.installAvailableUpdate() }
                                }
                                .keyboardShortcut(.defaultAction)
                            }
                        }
                    } else {
                        Text(manager.statusText)
                    }
                }

                GroupBox("Automation") {
                    LabeledContent("Background checks", value: "Every 24 hours")
                    LabeledContent("Open at Login", value: manager.loginItemStatusText)
                    if let lastChecked = manager.lastChecked {
                        LabeledContent("Last checked", value: lastChecked.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                if let errorMessage = manager.errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .padding(28)

            Spacer(minLength: 0)
        }
    }
}