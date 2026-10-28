#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
probe_output="${1:-$PWD/build/live-probe}"
mkdir -p "$probe_output"
probe_output="$(cd "$probe_output" && pwd)"
probe_app="$probe_output/OpenFirewall Network Probe.app"
mkdir -p "$probe_app/Contents/MacOS"
xcrun swiftc -parse-as-library Tests/Live/NetworkProbe.swift -framework SwiftUI -framework Network \
  -o "$probe_app/Contents/MacOS/NetworkProbe"
cat > "$probe_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.openfirewall.network-probe</string>
<key>CFBundleName</key><string>OpenFirewall Network Probe</string>
<key>CFBundleExecutable</key><string>NetworkProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$probe_app"
printf '%s\n' "$probe_app"
