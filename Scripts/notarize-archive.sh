#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 2 ]]; then
  echo "Usage: bash Scripts/notarize-archive.sh /path/Development.xcarchive /path/notarized-output" >&2
  exit 2
fi
notary_source="$(cd "$1" && pwd)"
mkdir -p "$2" build
notary_output="$(cd "$2" && pwd)"
[[ ! -e "$notary_output/OpenFirewall.app" ]] || { echo "Output already contains an app" >&2; exit 1; }
notary_work="$(mktemp -d "$PWD/build/notarization.XXXXXX")"
chmod 700 "$notary_work"
python3 - "$notary_source" "$notary_work" <<'PY'
from pathlib import Path
import hashlib
import plistlib
import subprocess
import sys
import tempfile

source, work = map(Path, sys.argv[1:])
source_app = source / 'Products/Applications/OpenFirewall.app'
subprocess.run([sys.executable, 'Scripts/check-build.py', str(source_app)], check=True)
signature = subprocess.run(['codesign', '-d', '--verbose=4', str(source_app)],
                           check=True, capture_output=True).stderr.decode()
if 'Authority=Apple Development:' not in signature and 'Authority=Mac Developer:' not in signature:
    raise SystemExit('Start with a development-signed archive. This helper is for Xcode-managed distribution signing.')
archive = work / 'OpenFirewall.xcarchive'
subprocess.run(['ditto', str(source), str(archive)], check=True)
app = archive / 'Products/Applications/OpenFirewall.app'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
team = info['SigningTeamIdentifier']
if not team:
    raise SystemExit('The development archive must have a signing team.')
with tempfile.TemporaryDirectory(prefix='openfirewall-archive-cert-') as directory:
    prefix = Path(directory) / 'certificate'
    subprocess.run(['codesign', '-d', '--extract-certificates=' + str(prefix), str(app)], check=True)
    identity = hashlib.sha1(Path(str(prefix) + '0').read_bytes()).hexdigest().upper()
provider = app / 'Contents/Library/SystemExtensions' / (info['FirewallFilterIdentifier'] + '.systemextension')
# Xcode's Developer ID export needs the system-extension variant of this entitlement.
# Change a PRIVATE copy only. Xcode replaces these staging signatures and profiles.
# This intermediate archive is not installable and must never be distributed.
for name, bundle in [('filter', provider), ('app', app)]:
    result = subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', str(bundle)],
                            check=True, capture_output=True)
    entitlements = plistlib.loads(result.stdout)
    if entitlements.get('com.apple.developer.team-identifier') != team:
        raise SystemExit('Archive signing teams differ.')
    entitlements['com.apple.developer.networking.networkextension'] = ['content-filter-provider-systemextension']
    entitlements.pop('get-task-allow', None)
    entitlements.pop('com.apple.security.get-task-allow', None)
    path = work / (name + '.entitlements')
    path.write_bytes(plistlib.dumps(entitlements))
    subprocess.run(['codesign', '--force', '--sign', identity, '--options', 'runtime', '--timestamp=none',
                    '--entitlements', str(path), str(bundle)], check=True)
options = {'method': 'developer-id', 'destination': 'upload', 'signingStyle': 'automatic',
           'teamID': team, 'manageAppVersionAndBuildNumber': False, 'stripSwiftSymbols': True}
(work / 'ExportOptions.plist').write_bytes(plistlib.dumps(options))
PY
notary_arguments=(-exportArchive -archivePath "$notary_work/OpenFirewall.xcarchive"
  -exportPath "$notary_work/Export" -exportOptionsPlist "$notary_work/ExportOptions.plist")
if [[ "${FIREWALL_PROVISION:-0}" == 1 ]]; then notary_arguments+=(-allowProvisioningUpdates); fi
xcodebuild "${notary_arguments[@]}"
if ! xcodebuild -exportNotarizedApp -archivePath "$notary_work/OpenFirewall.xcarchive" -exportPath "$notary_output"; then
  echo "Notarized export is not ready. Review Apple's status before retrying. Do not distribute the private archive." >&2
  printf 'Retry export: xcodebuild -exportNotarizedApp -archivePath %q -exportPath %q\n' \
    "$notary_work/OpenFirewall.xcarchive" "$notary_output" >&2
  exit 1
fi
python3 Scripts/check-release.py "$notary_output/OpenFirewall.app" --notarized
echo "Ready for packaging: $notary_output/OpenFirewall.app"
