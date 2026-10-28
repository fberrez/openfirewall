#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
probe_directory="$(mktemp -d "${TMPDIR:-/tmp}/openfirewall-identity.XXXXXX")"
trap 'rm -rf "$probe_directory"' EXIT
xcrun swiftc Sources/Core/Models.swift Sources/Shared/IdentityResolver.swift \
  Tests/Identity/IdentitySmoke.swift -framework Security -o "$probe_directory/identity-probe"
# This does not use a developer identity or touch any installed application.
/usr/bin/codesign --force --sign - --identifier com.apple.Notes "$probe_directory/identity-probe"
"$probe_directory/identity-probe"
