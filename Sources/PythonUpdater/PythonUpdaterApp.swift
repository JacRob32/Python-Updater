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
    @FocusState private var pythonPathIsFocused: Bool

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 16) {
                    AppIconView()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Python Updater")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text("Keep your official Python installation current.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await manager.checkForUpdatesNow() }
                    } label: {
                        Label("Check Now", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(manager.isChecking || manager.isInstalling)
                    .keyboardShortcut("r", modifiers: [.command])
                }
                .padding(28)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        UpdateSummary(manager: manager)

                        HStack(alignment: .top, spacing: 18) {
                            DashboardCard(title: "Installed Python", systemImage: "terminal") {
                                VStack(alignment: .leading, spacing: 12) {
                                    DetailRow(label: "Version", value: manager.installedVersionText)
                                    Divider()
                                    Text("Interpreter path")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 8) {
                                        TextField("/usr/local/bin/python3", text: $manager.editablePythonPath)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(.body, design: .monospaced))
                                            .focused($pythonPathIsFocused)
                                        Button("Save") {
                                            manager.setPythonPath(manager.editablePythonPath)
                                            Task { await manager.checkForUpdatesNow() }
                                        }
                                        .disabled(manager.editablePythonPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    }
                                }
                            }

                            DashboardCard(title: "Automation", systemImage: "clock") {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Check for updates")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Picker("Check for updates", selection: $manager.checkInterval) {
                                            ForEach(UpdateCheckInterval.allCases) { interval in
                                                Text(interval.rawValue).tag(interval)
                                            }
                                        }
                                        .labelsHidden()
                                        .frame(width: 120)
                                    }
                                    DetailRow(label: "Open at Login", value: manager.loginItemStatusText)
                                    if let lastChecked = manager.lastChecked {
                                        DetailRow(label: "Last checked", value: lastChecked.formatted(date: .abbreviated, time: .shortened))
                                    }
                                    Button("Manage Login Items") {
                                        manager.openLoginItemSettings()
                                    }
                                    .buttonStyle(.link)
                                }
                            }
                        }

                        if let errorMessage = manager.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(28)
                }
            }
        }
        .onAppear {
            pythonPathIsFocused = false
        }
    }
}

private struct UpdateSummary: View {
    @ObservedObject var manager: PythonUpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 22))
                    .foregroundStyle(statusColor)
                Text(statusTitle)
                    .font(.headline)
                Spacer()
                if manager.isChecking || manager.isInstalling {
                    ProgressView().controlSize(.small)
                }
            }

            if !manager.hasChecked && !manager.isChecking {
                Text("Ready to check for the latest official Python release.")
                    .foregroundStyle(.secondary)
            } else if manager.isChecking || manager.isInstalling {
                Text(manager.activityText).foregroundStyle(.secondary)
            } else if manager.updateAvailable {
                Text("Python \(manager.availableVersionText) is ready to install.")
                    .font(.title3.weight(.medium))
                HStack {
                    Button("View Release Notes") { manager.openReleasePage() }
                    Spacer()
                    Button {
                        Task { await manager.installAvailableUpdate() }
                    } label: {
                        Label("Install Update", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Text(manager.statusText).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
        }
    }

    private var statusSymbol: String {
        if manager.updateAvailable { return "arrow.down.circle.fill" }
        if manager.hasChecked { return "checkmark.circle.fill" }
        return "info.circle.fill"
    }

    private var statusColor: Color {
        if manager.updateAvailable { return .blue }
        if manager.hasChecked { return .green }
        return .secondary
    }

    private var statusTitle: String {
        if manager.updateAvailable { return "Update Available" }
        if manager.hasChecked { return "Up to Date" }
        return "Ready to Check"
    }
}

private struct DashboardCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage).font(.headline)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}

private struct AppIconView: View {
    var body: some View {
        Group {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? Color.blue.opacity(0.75) : Color.blue, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}