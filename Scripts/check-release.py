#!/usr/bin/env python3
"""Reject development-only builds before packaging a public macOS release."""
import argparse
import datetime
import fnmatch
import pathlib
import plistlib
import re
import subprocess
import sys
import tempfile


def run(*args):
    return subprocess.run(args, check=True, capture_output=True)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check(app, notarized):
    run(sys.executable, str(pathlib.Path(__file__).with_name('check-build.py')), str(app))
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    team = info['SigningTeamIdentifier']
    require(bool(team), 'A public release needs a signing team.')
    provider = app / 'Contents/Library/SystemExtensions' / (info['FirewallFilterIdentifier'] + '.systemextension')
    for bundle in (provider, app):
        metadata = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
        executable = bundle / 'Contents/MacOS' / metadata['CFBundleExecutable']
        require({'arm64', 'x86_64'} <= set(run('lipo', '-archs', str(executable)).stdout.decode().split()),
                f'{bundle.name}: expected an Apple Silicon and Intel universal binary.')
        run('codesign', '--verify', '--deep', '--strict', '--all-architectures', str(bundle))
        signature = run('codesign', '-d', '--verbose=4', str(bundle)).stderr.decode()
        require('Authority=Developer ID Application:' in signature,
                f'{bundle.name}: needs Developer ID Application signing, not development signing.')
        require(f'TeamIdentifier={team}' in signature, f'{bundle.name}: signing team mismatch.')
        flags = re.search(r'flags=0x([0-9a-fA-F]+)', signature)
        require(flags and int(flags[1], 16) & 0x10000, f'{bundle.name}: hardened runtime is missing.')
        require('Timestamp=' in signature and 'Timestamp=none' not in signature,
                f'{bundle.name}: a secure signing timestamp is missing.')
        entitlements = plistlib.loads(run('codesign', '-d', '--entitlements', '-', '--xml', str(bundle)).stdout)
        require(entitlements.get('com.apple.developer.networking.networkextension') ==
                ['content-filter-provider-systemextension'], f'{bundle.name}: wrong distribution entitlement.')
        for key in ('get-task-allow', 'com.apple.security.get-task-allow',
                    'com.apple.security.cs.disable-library-validation',
                    'com.apple.security.cs.allow-unsigned-executable-memory'):
            require(not entitlements.get(key, False), f'{bundle.name}: unsafe release entitlement {key}.')
        profile = plistlib.loads(run('security', 'cms', '-D', '-i',
                                     str(bundle / 'Contents/embedded.provisionprofile')).stdout)
        require(team in profile.get('TeamIdentifier', []), f'{bundle.name}: profile team mismatch.')
        require(profile.get('ProvisionsAllDevices') is True and not profile.get('ProvisionedDevices'),
                f'{bundle.name}: profile is restricted to development devices.')
        expiry = profile['ExpirationDate'].replace(tzinfo=datetime.timezone.utc)
        require(expiry > datetime.datetime.now(datetime.timezone.utc), f'{bundle.name}: profile has expired.')
        allowed = profile['Entitlements']
        require('content-filter-provider-systemextension' in
                allowed.get('com.apple.developer.networking.networkextension', []),
                f'{bundle.name}: profile does not authorize the filter entitlement.')
        identifier_key = 'com.apple.application-identifier'
        identifier = entitlements.get(identifier_key) or entitlements.get('application-identifier')
        allowed_identifier = allowed.get(identifier_key) or allowed.get('application-identifier')
        require(identifier and allowed_identifier and fnmatch.fnmatchcase(identifier, allowed_identifier),
                f'{bundle.name}: profile does not authorize the signed app identifier.')
        require(identifier.endswith('.' + metadata['CFBundleIdentifier']),
                f'{bundle.name}: signed app identifier does not match its bundle.')
        groups = entitlements.get('com.apple.security.application-groups', [])
        # macOS permits Team-ID-prefixed groups without a profile allowlist.
        # https://developer.apple.com/forums/thread/721701
        require(groups and all(group.startswith(team + '.') or any(fnmatch.fnmatchcase(group, pattern)
                                   for pattern in allowed.get('com.apple.security.application-groups', []))
                               for group in groups), f'{bundle.name}: profile does not authorize the app group.')
        if bundle == app:
            require(entitlements.get('com.apple.developer.system-extension.install') is True and
                    allowed.get('com.apple.developer.system-extension.install') is True,
                    'The app and profile must authorize system-extension installation.')
        with tempfile.TemporaryDirectory(prefix='openfirewall-cert-') as directory:
            prefix = pathlib.Path(directory) / 'certificate'
            run('codesign', '-d', '--extract-certificates=' + str(prefix), str(bundle))
            certificate = pathlib.Path(str(prefix) + '0').read_bytes()
            require(certificate in profile.get('DeveloperCertificates', []),
                    f'{bundle.name}: signing certificate is absent from its provisioning profile.')
    if notarized:
        run('xcrun', 'stapler', 'validate', str(app))
        run('spctl', '--assess', '--type', 'execute', '--verbose=2', str(app))
    print('Release checks passed: Developer ID, distribution profiles, hardened runtime, timestamps, '
          'Apple Silicon + Intel' + (', stapled notarization and Gatekeeper.' if notarized else '.'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=pathlib.Path)
    parser.add_argument('--notarized', action='store_true', help='Also require a stapled ticket and Gatekeeper acceptance.')
    args = parser.parse_args()
    try:
        check(args.app.resolve(), args.notarized)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f'Release check failed: {error}', file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print((error.stderr or error.stdout or b'').decode(errors='replace'), file=sys.stderr)
        sys.exit(1)
