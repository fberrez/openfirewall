#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 3 ]]; then
  echo "Usage: bash Scripts/package-release.sh /path/OpenFirewall.app /path/output v0.1.0-alpha.1" >&2
  exit 2
fi
release_app="$(cd "$1" && pwd)"
mkdir -p "$2"
release_output="$(cd "$2" && pwd)"
release_tag="$3"
[[ "$release_tag" =~ ^v?[0-9][a-zA-Z0-9.+-]*$ ]] || { echo "Invalid release tag" >&2; exit 2; }
release_version="${release_tag#v}"
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$release_app/Contents/Info.plist")"
[[ "${release_version%%-*}" == "$app_version" ]] || { echo "Release tag and app version differ" >&2; exit 2; }
python3 Scripts/check-release.py "$release_app" --notarized
release_name="OpenFirewall-${release_version}-universal.dmg"
release_dmg="$release_output/$release_name"
[[ ! -e "$release_dmg" ]] || { echo "Refusing to overwrite an existing release image" >&2; exit 1; }
release_temporary="$(mktemp -d "${TMPDIR:-/tmp}/openfirewall-package.XXXXXX")"
release_mounted=0
cleanup() {
  if [[ "$release_mounted" == 1 ]]; then hdiutil detach "$release_temporary/mounted" >/dev/null || true; fi
  rm -rf "$release_temporary"
}
trap cleanup EXIT
mkdir -p "$release_temporary/image" "$release_temporary/mounted"
ditto "$release_app" "$release_temporary/image/OpenFirewall.app"
ln -s /Applications "$release_temporary/image/Applications"
cp LICENSE "$release_temporary/image/LICENSE.txt"
cat > "$release_temporary/image/Install.txt" <<'INSTALL'
OpenFirewall — Your apps. Your rules.

1. Drag OpenFirewall to Applications.
2. Open OpenFirewall from Applications.
3. In Setup, click Enable firewall.
4. Approve the system extension and network filter when macOS asks.
5. In Applications, click + Add app. Select an app, then choose Allow or Block.

Apps are allowed by default. Quitting the interface leaves an enabled filter running.
To stop filtering, open Setup and click Disable firewall.

Requires macOS 14 or later. This is an early alpha.
Free and open source under the MIT license. No developer account is needed to install.
Source, support, and known limitations: https://github.com/fberrez/openfirewall
INSTALL
hdiutil create -volname OpenFirewall -srcfolder "$release_temporary/image" -format UDZO "$release_dmg"
hdiutil verify "$release_dmg"
hdiutil attach "$release_dmg" -readonly -nobrowse -mountpoint "$release_temporary/mounted" >/dev/null
release_mounted=1
python3 Scripts/check-release.py "$release_temporary/mounted/OpenFirewall.app" --notarized
hdiutil detach "$release_temporary/mounted" >/dev/null
release_mounted=0
(cd "$release_output" && shasum -a 256 "$release_name" > SHA256SUMS && shasum -a 256 -c SHA256SUMS)
echo "Verified installer image: $release_dmg"
