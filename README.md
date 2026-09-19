# Python Updater

Python Updater is a small macOS app that checks the official Python.org releases, lets you review an available update, and opens Apple's Installer app to install it. It never asks for your administrator password itself.

## Using the App

1. Open **Python Updater** from Applications. It appears in the Dock while open and adds a small menu-bar icon; clicking that icon brings the app window back.
2. Under **Installed Python**, confirm the interpreter path. The default is `/usr/local/bin/python3`. Homebrew users will commonly use `/opt/homebrew/bin/python3`.
3. Click **Check Now**. The app compares your installed version with the latest stable Python 3 release from Python.org.
4. When an update is available, choose **View Release Notes** or **Install Update**. The app downloads the official macOS package, verifies its SHA-256 checksum, then opens Installer.app.
5. Choose Daily, Weekly, or Monthly checks under **Automation**. The app also registers itself in macOS Login Items, so scheduled checks continue after you sign in.

You can manage the Login Item from the app's **Manage Login Items** link or in **System Settings > General > Login Items**.

## Build a DMG

On a Mac with the Xcode Command Line Tools installed, run this from the project folder:

```sh
chmod +x Scripts/build-dmg.sh
Scripts/build-dmg.sh
```

The finished disk image is written to `dist/Python-Updater-1.0.dmg`. The script creates an application bundle, includes `icon.icns`, signs the app and disk image, and verifies both signatures.

By default the script uses an ad-hoc signature. This is useful for local testing and sharing with people who understand macOS security prompts, but it does not satisfy Gatekeeper for public distribution. To distribute outside your own Mac without warnings, build with a Developer ID certificate and notarize the resulting DMG:

```sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" Scripts/build-dmg.sh
```

The bundle identifier defaults to `com.example.PythonUpdater`. Replace it for a distributed build:

```sh
BUNDLE_IDENTIFIER="com.yourcompany.pythonupdater" Scripts/build-dmg.sh
```

## Technical Details

The app only accepts the current stable Python 3 release and downloads the official HTTPS `.pkg` installer published by Python.org. It validates the downloaded package against Python.org's published SHA-256 checksum before opening it. The app's icon is `icon.icns` and is used by the dashboard, the `.app`, and the generated `.dmg`.