# Verification

## Local installation: verified

On 2026-10-28, a development Mac running macOS 26.2 on Apple Silicon ran a properly provisioned and signed Release build from Applications. macOS approved and enabled the system extension. The following checks passed:

- Actual TCP and UDP responses with Allow, no responses with Block, and restored responses with Allow.
- A real, already open TCP connection was disconnected by Block. The flow identifier remained the same while its recorded decision and state changed to blocked. The client received a disconnected-socket error.
- The same existing-flow check passed through the GUI after selecting the test app from the installed-app picker.
- Blocking remained active with the UI process closed. The saved rule appeared after reopening the UI.
- Real connection metadata, byte counters, closed-flow states, and decision filters appeared in the monitor.
- Installed-app search, adding Notes, removing temporary rules, and rule acknowledgements worked.
- Built-bundle APPL/SYSX declarations, embedded provider class, versions, identifiers, Mach service prefix, signatures, and embedded profiles passed the artifact checker.

Ten core tests and the Security.framework identity smoke test also passed. CI repeats these checks and builds the unsigned app. Real connection histories, signing profiles, and local diagnostic artifacts are not part of this repository. No reboot, provider-crash, or all-network-path claim follows from the local checks.

## Public alpha artifact checks

Version `0.1.0-alpha.1` uses app version `0.1.0`, build `4`. Both executables contain Apple Silicon and Intel slices. Developer ID signatures, secure timestamps, hardened runtime, and distribution profiles passed validation. The profiles authorize all devices and contain no development-device list. The app's stapled notarization ticket validated and Gatekeeper accepted it.

The packaging helper mounts the completed DMG read-only and repeats those checks on its app. It verifies the disk-image checksum and writes `SHA256SUMS`. These are artifact checks, not proof of enforcement on every Mac. Only Apple Silicon has received live device testing; Intel remains untested on hardware.

Switching an existing installation from development signing to Developer ID exposed a cached macOS signing requirement in the old network-filter configuration. Migration requires recreating that owned configuration and approving filtering again. The local rule file is retained. Setup now checks whether the bundled extension is already enabled before submitting another activation request, and retains its requests until completion.

## Broader distribution testing

The checklist below covers a public release across machines and network configurations. Some items combine a locally verified behavior with additional scenarios. An unchecked item means the whole combined item has not been qualified for distribution.

Use a disposable test app with its own signing identifier and a TCP/UDP client. Blocking a shared system helper can affect more than one application.

`bash Scripts/build-probe.sh` builds a separate ad-hoc signed app for these tests. It sends a TCP HTTP request to example.com and a UDP STUN binding request to Cloudflare's public STUN service. It saves only success, timing, and response length beside the test app. It does not change firewall rules. Establish that both requests succeed before testing a Block rule, then verify Block → failure → Allow → success while checking matching flow records in OpenFirewall.

- [x] Both targets sign with the same team and correct capabilities. The extension is embedded in `Contents/Library/SystemExtensions` and its signature verifies.
- [ ] Installing under `/Applications` and choosing Enable triggers the expected system-extension and network-filter approvals. Declining approval leaves a useful, recoverable setup state.
- [ ] The signed app connects to the extension. The UI reports “Filtering connections.” A different team or bundle identifier cannot read or change policy through XPC.
- [ ] A TCP connection made by the test app appears with the expected verified identity, endpoint, direction, and decision.
- [ ] A Block rule prevents a new connection from that app. Another app can still reach the same destination.
- [ ] An explicit Allow rule overrides a Block default. Removing that rule restores the Block default.
- [ ] A new Block rule drops an already open, retained TCP connection. Allow requires a fresh connection.
- [ ] UDP flows, IPv4, IPv6, and incoming connections receive the expected app rule. Test local, remote, and VPN routes separately.
- [ ] A helper's identity matches what macOS attributes. Rule creation from an observed connection and from the same selected executable creates the same key.
- [ ] Reports increase byte counters and mark closed flows. Clear and JSON export behave as described. No payload contents appear in logs or history.
- [ ] Rules remain after quitting the UI, restarting the extension, and rebooting. Preview edits do not persist.
- [ ] Rapid rule changes preserve the latest revision. An unavailable extension produces an unconfirmed-update message.
- [ ] Changing the filter state in System Settings updates the UI. Disable stops verdict enforcement. Re-enable restores the saved policy.
- [ ] Exercise long-lived flows and the tracking limit. Confirm the warning and document the limitation.
- [ ] Check CPU, memory, flow latency, and recovery from extension crashes under load. OS behavior during provider failure is not claimed to be fail-closed.
- [ ] Verify app updates, extension replacement, multi-user behavior, notarization, and removal before a public release.

Do not mark a checkbox complete based only on an unsigned build, a unit test, or preview data.
