#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
xcodegen generate
build_configuration="${FIREWALL_BUILD_CONFIGURATION:-Release}"
build_arguments=(-project OpenFirewall.xcodeproj -scheme OpenFirewall -configuration "$build_configuration"
  -derivedDataPath "${FIREWALL_BUILD_DIR:-build}")
for setting_name in FIREWALL_APP_ID FIREWALL_FILTER_ID FIREWALL_NETWORK_ENTITLEMENT; do
  if [[ -n "${!setting_name:-}" ]]; then build_arguments+=("$setting_name=${!setting_name}"); fi
done
if [[ -n "${FIREWALL_TEAM_ID:-}" ]]; then
  build_arguments+=("DEVELOPMENT_TEAM=$FIREWALL_TEAM_ID")
  if [[ "${FIREWALL_PROVISION:-0}" == 1 ]]; then
    build_arguments+=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration)
  fi
else
  build_arguments+=(CODE_SIGNING_ALLOWED=NO)
fi
xcodebuild "${build_arguments[@]}" build
python3 Scripts/check-build.py "${FIREWALL_BUILD_DIR:-build}/Build/Products/$build_configuration/OpenFirewall.app"
if [[ -z "${FIREWALL_TEAM_ID:-}" ]]; then
  echo "Unsigned UI build. Live filtering requires a properly signed build and macOS approval."
fi
echo "App: ${FIREWALL_BUILD_DIR:-$PWD/build}/Build/Products/$build_configuration/OpenFirewall.app"
