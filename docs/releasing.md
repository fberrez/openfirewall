# Releasing OpenFirewall

Public downloads must contain a Developer ID-signed, notarized app with distribution profiles. A development-signed build only works on registered devices and is not a public release.

## Archive

Use a clean checkout. Run the core tests and identity smoke test. Set the app version and build number in `project.yml`, then generate the Xcode project. Archive both architectures using the same team and identifiers for the app and filter:

```sh
xcodegen generate
xcodebuild -project OpenFirewall.xcodeproj -scheme OpenFirewall \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath build/OpenFirewall.xcarchive archive \
  DEVELOPMENT_TEAM=YOURTEAMID \
  FIREWALL_APP_ID=co.yourdomain.openfirewall \
  FIREWALL_FILTER_ID=co.yourdomain.openfirewall.filter \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO
```

Sign into Xcode first. Use identifiers and profiles belonging to your team. Add `-allowProvisioningUpdates` only when you want Xcode to create or update provisioning assets. The archive above uses development signing; do not distribute it.

## Distribution signing and notarization

```sh
FIREWALL_PROVISION=1 bash Scripts/notarize-archive.sh \
  build/OpenFirewall.xcarchive build/notarized
```

This uses Xcode's signed-in account and automatic Developer ID distribution workflow. Cloud-managed signing can be used when the account has access. The script does not export private keys or require credentials in the repository. Omit `FIREWALL_PROVISION=1` to use existing provisioning assets without permitting updates.

Network Extension entitlements differ between development and Developer ID distribution. The helper makes a private copy of the archive and changes the network entitlement to `content-filter-provider-systemextension`. It re-signs this intermediate copy with the archive's existing development identity so Xcode can process it. Xcode then replaces the intermediate signatures and profiles with Developer ID distribution signing and submits the app to Apple. **The intermediate archive is not a release and must never be distributed.** It remains in an ignored, private build directory for diagnostics or retrying an export.

After Apple accepts notarization, the helper exports the notarized app and runs `check-release.py --notarized`. If notarization is still processing or fails, the script stops and prints the export command for the private archive. Review Apple's status and any errors before retrying. Never substitute the development or intermediate app for the notarized export.

## Package and verify

```sh
bash Scripts/package-release.sh \
  build/notarized/OpenFirewall.app dist/v0.1.0-alpha.1 v0.1.0-alpha.1
```

The package helper creates a read-only disk image with the app, an Applications shortcut, installation instructions, and the MIT license. It refuses to overwrite an existing image. The disk image is a delivery container; the app and its embedded provider carry the Developer ID signatures, and the app carries the stapled notarization ticket. This workflow does not claim a separate notarization ticket for the disk image itself.

Before and after packaging, validation checks:

- Both executables contain Apple Silicon and Intel slices.
- App and provider signatures verify and use Developer ID Application certificates from the expected team.
- Hardened runtime and secure signing timestamps are present; debug entitlements are absent.
- Distribution profiles are unexpired, authorize all devices, and match the signing certificate and required capabilities.
- App identifiers, bundle types, versions, app-group/Mach-service settings, and the embedded provider agree.
- The app's stapled ticket validates and Gatekeeper accepts it.

The helper mounts the completed image read-only and repeats validation on the app inside it. It also writes and verifies `SHA256SUMS`.

## Publish

Perform the appropriate signed-device checks in [VERIFY.md](../VERIFY.md). Record exactly which devices and network paths were tested. Use an alpha or prerelease label while broader validation is incomplete.

Commit the matching source, tag that commit, and publish the DMG and `SHA256SUMS` together through GitHub Releases. Keep archives, profiles, signing credentials, private diagnostic logs, and connection histories out of release assets. GitHub generates the source archives from the tag.

Update the README download link, release notes, and verification record. Never describe a build as notarized based only on a successful upload or an unsigned CI build.
