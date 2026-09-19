#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
product_name="Python Updater"
executable_name="PythonUpdater"
version=${VERSION:-1.0}
bundle_identifier=${BUNDLE_IDENTIFIER:-com.example.PythonUpdater}
signing_identity=${CODE_SIGN_IDENTITY:--}
dist_directory="$project_root/dist"
work_directory=$(mktemp -d "${TMPDIR:-/tmp}/PythonUpdater.XXXXXX")
bundle_path="$work_directory/$product_name.app"
staging_directory="$work_directory/dmg-staging"
staged_bundle_path="$staging_directory/$product_name.app"
dmg_path="$dist_directory/Python-Updater-$version.dmg"

trap 'rm -rf "$work_directory"' EXIT

rm -f "$dmg_path"
mkdir -p "$bundle_path/Contents/MacOS" "$bundle_path/Contents/Resources" "$staging_directory"

swiftc \
    "$project_root/Sources/PythonUpdater/PythonUpdaterApp.swift" \
    "$project_root/Sources/PythonUpdater/PythonUpdateManager.swift" \
    -o "$bundle_path/Contents/MacOS/$executable_name" \
    -framework AppKit \
    -framework SwiftUI \
    -framework ServiceManagement

cp "$project_root/Supporting Files/Info.plist" "$bundle_path/Contents/Info.plist"
cp "$project_root/icon.icns" "$bundle_path/Contents/Resources/icon.icns"
plutil -replace CFBundleIdentifier -string "$bundle_identifier" "$bundle_path/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$bundle_path/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$version" "$bundle_path/Contents/Info.plist"
xattr -cr "$bundle_path"
xattr -d com.apple.FinderInfo "$bundle_path" 2>/dev/null || true
xattr -r -d com.apple.FinderInfo "$bundle_path" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$bundle_path" 2>/dev/null || true
xattr -r -d 'com.apple.fileprovider.fpfs#P' "$bundle_path" 2>/dev/null || true

codesign --force --sign "$signing_identity" --timestamp=none "$bundle_path"
codesign --verify --deep --strict --verbose=2 "$bundle_path"

ditto --norsrc "$bundle_path" "$staged_bundle_path"
xattr -cr "$staged_bundle_path"
xattr -d com.apple.FinderInfo "$staged_bundle_path" 2>/dev/null || true
xattr -r -d com.apple.FinderInfo "$staged_bundle_path" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$staged_bundle_path" 2>/dev/null || true
xattr -r -d 'com.apple.fileprovider.fpfs#P' "$staged_bundle_path" 2>/dev/null || true
codesign --force --sign "$signing_identity" --timestamp=none "$staged_bundle_path"
codesign --verify --deep --strict --verbose=2 "$staged_bundle_path"
ln -s /Applications "$staging_directory/Applications"
hdiutil create -volname "$product_name" -srcfolder "$staging_directory" -format UDZO -ov "$dmg_path"
codesign --force --sign "$signing_identity" --timestamp=none "$dmg_path"
codesign --verify --verbose=2 "$dmg_path"

print "Created $dmg_path"
