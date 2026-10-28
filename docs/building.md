# Building and installation

## Requirements

- macOS 14 or later. Live testing has used Apple Silicon and macOS 26.2.
- Xcode with Swift 6 or later, selected as the active developer directory.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), available through `brew install xcodegen`.
- For live filtering: an Apple Developer team with the necessary capabilities, a development signing identity, and valid provisioning profiles for both targets.

The Swift package covers the policy engine. The macOS interface and network system extension build through Xcode.

## Unsigned interface and preview

```sh
swift test
bash Scripts/test-identity.sh
bash Scripts/build.sh
open build/Build/Products/Release/OpenFirewall.app
```

Choose **Explore preview**. Sample connections and rule changes stay in preview. This build cannot activate the real network filter.

The source includes a generated `OpenFirewall.xcodeproj`. `project.yml` is the source of truth. The build script runs XcodeGen before building and checks the resulting app and embedded extension afterward.

## Enable live filtering

1. Sign into your Apple Developer account in **Xcode → Settings → Accounts**.
2. Open `OpenFirewall.xcodeproj`. Use the same signing team for **OpenFirewall** and **OpenFirewallFilter**.
3. Choose unique `FIREWALL_APP_ID` and `FIREWALL_FILTER_ID` values that your team can provision. Both targets must receive the same build settings.
4. Provision Network Extensions with the development `content-filter-provider` entitlement for both targets. The app also requires `com.apple.developer.system-extension.install`. The generated app group and Mach service must share the provisioning team's prefix.
5. Build the signed app. The command below passes the identifiers and team to both targets.

```sh
FIREWALL_TEAM_ID=YOURTEAMID \
FIREWALL_APP_ID=co.yourdomain.openfirewall \
FIREWALL_FILTER_ID=co.yourdomain.openfirewall.filter \
bash Scripts/build.sh
```

Set `FIREWALL_PROVISION=1` for this command if you want Xcode to create or update profiles and register the current Mac. Otherwise the script uses profiles already available on the machine.

6. Copy the resulting signed `OpenFirewall.app` to `/Applications`.
7. Open it. Choose **Setup → Enable firewall** and complete the system-extension and content-filter approval prompts in macOS. The app provides a shortcut to System Settings when needed.
8. Wait for the interface to confirm filtering and rule acknowledgements before relying on a rule. Follow [VERIFY.md](../VERIFY.md) to test actual network behavior.

Apple signing and approval are platform requirements. OpenFirewall has no product activation, license check, or account. The build does not disable System Integrity Protection or bypass macOS approval.

## Build options

| Environment variable | Purpose |
| --- | --- |
| `FIREWALL_TEAM_ID` | Signing team. An empty value produces an unsigned build. |
| `FIREWALL_APP_ID` | Main app bundle identifier. Default: `org.openfirewall.app`. |
| `FIREWALL_FILTER_ID` | Filter bundle identifier. Default: `org.openfirewall.filter`. |
| `FIREWALL_BUILD_DIR` | Derived data location. Default: `build`. |
| `FIREWALL_BUILD_CONFIGURATION` | Xcode configuration. Default: `Release`. |
| `FIREWALL_PROVISION` | Set to `1` to explicitly permit provisioning updates and device registration. |
| `FIREWALL_NETWORK_ENTITLEMENT` | Network Extension entitlement value. Default: `content-filter-provider`. |

Identifiers also configure the Info keys, Mach service, app group, and embedded product name. Do not edit only one bundle identifier. Do not commit personal signing settings or provisioning files.

## Troubleshooting

**The app only offers preview.** The default build is unsigned. Live filtering requires valid signatures and profiles, installation in Applications, and macOS approval.

**Xcode cannot find profiles.** Confirm the selected team has the required capabilities and that both identifiers belong to it. Sign into Xcode and explicitly permit provisioning updates if needed.

**“Does not appear to belong to any extension categories.”** Rebuild from the current project. The embedded extension must declare `CFBundlePackageType = SYSX`; the app must declare `APPL`. `Scripts/check-build.py` checks both in the built product.

**Approval is pending.** Complete the requests in System Settings. macOS may require your password. A pending request does not mean filtering is active.

**A rule shows an unconfirmed update.** The interface has not received an extension acknowledgement. Check Setup and the system extension's state before testing again.

**An app still connects.** Confirm which app or helper appears in Connections. Rules follow the source identity supplied by macOS. A helper may need its own rule. A pinned-build rule may also need to be recreated after an executable update.

## Public distribution

Development signing uses `content-filter-provider`. Developer ID distribution uses `content-filter-provider-systemextension` and requires matching Developer ID profiles and a Developer ID identity. [Apple's signing explanation](https://developer.apple.com/forums/thread/737894) describes the distinction.

A public binary release still needs a complete Developer ID signing and notarization workflow, update and removal testing, and broader signed-device validation. The repository currently provides source, not a notarized installer. Never distribute a development certificate, private key, or provisioning credentials.

Apple references: [Network Extension deployment](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment), [installing system extensions](https://developer.apple.com/documentation/systemextensions/installing-system-extensions-and-drivers).
