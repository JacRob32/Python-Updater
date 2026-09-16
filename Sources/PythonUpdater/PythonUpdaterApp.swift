import AppKit
import SwiftUI

@main
struct PythonUpdaterApp: App {
    init() {
        PythonUpdateManager.shared.start()
    }

    var body: some Scene {
        MenuBarExtra("Python Updater", systemImage: "arrow.triangle.2.circlepath") {
            Button("Check for Updates") {
                Task {
                    await PythonUpdateManager.shared.checkForUpdatesNow()
                }
            }

            Divider()

            Button("Quit Python Updater") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}