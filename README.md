# Python Updater

A native macOS dashboard for checking and installing official Python updates. Its menu-bar icon only restores the main app window.

## Open in Xcode

1. In Xcode, create a macOS **App** named `PythonUpdater` with SwiftUI lifecycle and macOS 13 or later as its deployment target.
2. Replace the generated app source with the files in `Sources/PythonUpdater`.
3. Use `Supporting Files/Info.plist` as the target's Info.plist and set its bundle identifier to your own reverse-DNS identifier. `LSUIElement` is intentionally absent, so the app appears in the Dock when open.
4. Add `icon.icns` to the target's **Copy Bundle Resources** build phase. The Info.plist names it as the bundle icon, so it is used by the app and when distributing an `.app` or `.dmg`.
5. Do not add `LSBackgroundOnly`; the app needs to activate its main window when the menu-bar icon is clicked.
6. Code-sign the app. `SMAppService.mainApp.register()` then registers the app itself in Login Items on its first launch. Users can manage it in System Settings > General > Login Items.

## Configuration

The updater checks `/usr/local/bin/python3` by default. Open the main app window and select **Check Now** to test the complete update flow on demand. To watch a different interpreter, set the `PythonExecutablePath` user-default value for the app's bundle identifier, for example:

```sh
defaults write com.example.PythonUpdater PythonExecutablePath -string /opt/homebrew/bin/python3
```

The app only accepts the current stable Python 3 release and downloads the official HTTPS `.pkg` installer that python.org publishes for it. It validates the package against python.org's SHA-256 before opening it with Installer.app.

## Local Validation

Run `swift build` to compile the source package. Xcode uses the same Swift source files, while it supplies the macOS application bundle and the Info.plist.