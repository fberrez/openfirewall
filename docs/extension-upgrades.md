# Extension upgrades

Alpha.2 is withheld pending isolated upgrade validation. Do not test replacement of the active extension on the developer's working Mac.

## Observed failure

On macOS 26.2, replacing the active Developer ID-signed build 6 with notarized build 7 produced a new, enabled provider, but its control listener failed with `Operation not permitted`. The app lost its XPC connection, local TCP/UDP probes timed out, and new GitHub requests through the system's local proxy timed out. Restarting the owned filter did not repair the listener.

Restoring build 6 restored XPC, all four IPv4/IPv6 TCP/UDP echo checks, and GitHub access. The original two user rules were retained. No proxy, VPN, or other security-agent settings were changed. Build 7 was never published.

## Candidate workaround

The app and provider previously reused the same Mach service name across builds. Apple DTS describes a matching Network Extension upgrade issue, tracked as FB17032197, and suggests changing the Mach service name for each version. See [XPC connection consistently invalidated on app upgrade](https://developer.apple.com/forums/thread/779395).

Build 8 declares `$(FIREWALL_GROUP_ID).control.$(CURRENT_PROJECT_VERSION)` in both bundles and the provider's `NEMachServiceName`. The app-group identifier stays stable. Signature and owner checks are unchanged. Bundle validation rejects an unversioned service or mismatched names. XPC interruption now clears only the affected connection so polling can reconnect.

This addresses the observed control-channel collision. It does not establish that every network stall has the same cause, or that replacement is reliable on supported macOS versions.

## Release gate

Use a disposable Mac or a macOS VM with a snapshot. Keep the working developer Mac's installed extension unchanged.

1. Install and enable a previously released build. Add an isolated test identity; save the policy.
2. Establish successful TCP and UDP probes before replacement.
3. Install the candidate, replace its extension, and verify that the loaded executable matches the candidate.
4. Verify authenticated XPC and that both new and retained connections behave as expected.
5. Run IPv4/IPv6 loopback TCP/UDP Allow → Block → Allow against unchanged echo endpoints. Include a local-proxy path and direct remote traffic.
6. Check policy preservation, reconnect after UI restart, and a second upgrade to a different versioned service.
7. Restore the snapshot. Repeat with the old filter already enabled and already disabled.

Publish the signed alpha.2 artifact only after recording these results. Signing, notarization, and unsigned CI checks alone do not satisfy this gate.
