# Architecture and rule behavior

OpenFirewall uses Apple's public NetworkExtension, SystemExtensions, and Security frameworks. The app has no third-party runtime dependencies.

## Flow decisions

The system extension runs an `NEFilterDataProvider`. It requests socket flows from macOS and resolves each source app's identity from `sourceAppAuditToken` using Security.framework.

The policy has one explicit action per exact app identity. An explicit rule wins; otherwise the configured default applies. The initial default is Allow. A new matching flow receives an Allow or Drop verdict.

An Allow-to-Block change also updates retained, allowed flows to Drop. An already dropped connection must reconnect after an Allow change. The extension keeps at most 16,384 allowed flow references. Once that limit is reached, new flows still receive decisions, but some existing flows cannot be revoked by a later update. The interface reports the limit.

Coverage is limited to socket flows macOS delivers to the provider. This is not a packet-layer policy. Attribution and coverage for helpers, system services, VPNs, IPv6, and incoming traffic require scenario-specific testing.

## App identity

- Valid Apple-anchored signatures use the team identifier and signing identifier. These rules survive normal updates that retain the same identity.
- Valid Apple platform binaries without a team identifier use a separate Apple-platform namespace.
- Other valid signatures, including ad-hoc signatures, use a validated code-directory hash. The interface calls these **Pinned build** rules. Changing the executable changes its identity.
- Unverified or unsigned processes use the default action. The app does not create a broad rule for an unidentified process.

Process names, PIDs, and file paths do not authorize an application. Selecting a file and observing its running process use the same identity scheme. A helper can have a distinct identity even when it belongs to another app.

## Policy and local control

The UI serializes policy writes, persists them in macOS network-filter preferences, and sends them to the provider over local XPC. Updates carry revisions. Stale revisions and conflicting content at the same revision are rejected. **Rules applied** means the provider acknowledged the change. A missing acknowledgement is shown as unconfirmed.

Both sides authenticate the expected bundle identifier, signing team, and Apple anchor. The provider also checks the effective UID of the user who configured it. The extension limits incoming control connections and message sizes. There is no listening network service.

The app keeps a local rule copy at `~/Library/Application Support/OpenFirewall/rules.json`. Its directory uses mode `0700`; the file uses `0600`. The provider reads persisted policy at startup. A malformed saved policy fails startup rather than silently substituting an Allow default.

Quitting the app does not stop an enabled system extension. Use **Setup → Disable firewall** to stop filtering. The extension can remain installed while disabled. Provider-crash behavior is not guaranteed to block traffic.

## Connection monitor

The provider requests macOS statistics reports about every five seconds. It retains the latest 500 metadata records in memory. The UI polls over XPC every two seconds. History resets when the provider stops.

Records include the attributed application, destination, port, protocol, direction, decision, state, and cumulative byte counts. Short or blocked flows can show zero bytes. Older records are evicted.

The provider does not request payload peeks, decrypt TLS, rewrite DNS, or parse ECH. Hostnames are shown when macOS supplies them. OpenFirewall does not claim to independently discover every hostname.

**Export** saves all retained records captured when Export was selected. Search and decision filters affect the table, not the export. **Clear** removes history without changing rules or disconnecting apps. Exports can contain sensitive app names, paths, and destinations; review them before sharing.

## Source map

| Path | Purpose |
| --- | --- |
| `Sources/Core` | Policy model, exact rule matching, revisions, bounded history |
| `Sources/Shared` | Verified identities and authenticated XPC contract |
| `Sources/Filter` | Socket-flow verdicts, reports, policy application, live revocation |
| `Sources/App` | SwiftUI interface, installed-app chooser, setup, persistence, XPC client |
| `Tests/CoreTests` | Policy and history tests |
| `Tests/Identity` | Real Security.framework identity smoke test |
| `Tests/Live` | Separate TCP/UDP test application |
| `project.yml` | XcodeGen project definition and capabilities |

Apple references: [Content filter providers](https://developer.apple.com/documentation/networkextension/content-filter-providers), [source app audit token](https://developer.apple.com/documentation/networkextension/nefilterflow/sourceappaudittoken), [System Extensions](https://developer.apple.com/documentation/systemextensions).
