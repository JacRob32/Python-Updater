# Python Updater

An invisible SwiftUI macOS app that checks python.org daily and asks before opening the official Python installer package.

## Open in Xcode

1. In Xcode, create a macOS **App** named `PythonUpdater` with SwiftUI lifecycle and macOS 13 or later as its deployment target.
2. Replace the generated app source with the files in `Sources/PythonUpdater`.
3. In the target's **Info** tab, add `Application is agent (UIElement)` and set it to `YES`. This writes `LSUIElement = YES`, which hides the Dock icon while retaining the app's menu-bar control.
4. Do not add `LSBackgroundOnly`. An app with that setting cannot reliably become active to present its update alert.
5. Set the bundle identifier in `Supporting Files/Info.plist` to your own reverse-DNS identifier and use that file as the target's Info.plist.
6. Code-sign the app. `SMAppService.mainApp.register()` then registers the app itself in Login Items on its first launch. Users can manage it in System Settings > General > Login Items.

## Configuration

The updater checks `/usr/local/bin/python3` by default. Select the menu-bar icon and choose **Check for Updates** to test the complete update flow on demand. To watch a different interpreter, set the `PythonExecutablePath` user-default value for the app's bundle identifier, for example:

```sh
defaults write com.example.PythonUpdater PythonExecutablePath -string /opt/homebrew/bin/python3
```

The app only accepts the current stable Python 3 release and downloads the official HTTPS `.pkg` installer that python.org publishes for it. It validates the package against python.org's SHA-256 before opening it with Installer.app.

## Local Validation

Run `swift build` to compile the source package. Xcode uses the same Swift source files, while it supplies the macOS application bundle and the Info.plist.