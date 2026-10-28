#!/usr/bin/env python3
"""Check the produced bundles, not just the project inputs or core unit tests."""
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
def info(bundle):
    with (bundle / 'Contents/Info.plist').open('rb') as stream:
        return plistlib.load(stream)

container = info(app)
assert container.get('CFBundlePackageType') == 'APPL', 'Container is not an APPL bundle'
assert container['CFBundleIdentifier'] == container['FirewallAppIdentifier']
identifier = container['FirewallFilterIdentifier']
provider = app / 'Contents/Library/SystemExtensions' / (identifier + '.systemextension')
extension = info(provider)
assert extension.get('CFBundlePackageType') == 'SYSX', 'Network extension must declare SYSX'
assert extension['CFBundleIdentifier'] == identifier
assert extension['CFBundleVersion'] == container['CFBundleVersion']
assert extension['CFBundleShortVersionString'] == container['CFBundleShortVersionString']
assert (provider / 'Contents/MacOS' / extension['CFBundleExecutable']).is_file()
assert extension['NetworkExtension']['NEProviderClasses']['com.apple.networkextension.filter-data'] == 'FilterDataProvider'
service = extension['NetworkExtension']['NEMachServiceName']
assert service == container['FirewallMachService'] == extension['FirewallMachService']
assert container['SigningTeamIdentifier'] == extension['SigningTeamIdentifier']
if container['SigningTeamIdentifier']:
    for bundle in (app, provider):
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
        result = subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', str(bundle)],
                                check=True, capture_output=True)
        entitlements = plistlib.loads(result.stdout)
        assert entitlements['com.apple.developer.team-identifier'] == container['SigningTeamIdentifier']
        assert any(service.startswith(group + '.') for group in entitlements['com.apple.security.application-groups'])
        assert entitlements['com.apple.developer.networking.networkextension'] in (
            ['content-filter-provider'], ['content-filter-provider-systemextension'])
        assert (bundle / 'Contents/embedded.provisionprofile').is_file(), 'Missing provisioning profile'
print(f'Bundle checks passed: APPL + SYSX, provider class, matching versions, identifiers, Mach service'
      f'{", signatures and profiles" if container["SigningTeamIdentifier"] else " (unsigned)"}.')
