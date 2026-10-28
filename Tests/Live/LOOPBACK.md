# Loopback regression test

Requires macOS and an installed, enabled, properly signed OpenFirewall extension. Use an isolated probe identity and preserve all existing user rules.

`loopback-echo.py PORTS.json` binds TCP and UDP echo servers to loopback only. It records the assigned ports. The optional `127.0.0.2` case is skipped when that alias is not assigned; the script does not change network interfaces.

Compile `LoopbackProbe.swift` into a separate application bundle and sign that test bundle. The executable accepts `tcp|udp HOST PORT` and exits 0 only when it receives its exact random payload back. It accepts only loopback addresses. It never changes rules or proxy settings.

1. Start the echo servers and keep them running.
2. Add a rule for the probe's verified identity. Keep the same signed binary throughout the test.
3. With Allow, verify that every listed endpoint echoes successfully.
4. With Block, run a fresh probe process against each endpoint. Every attempt must fail; a timeout alone is insufficient unless Allow succeeds against the same endpoint before and after.
5. Restore Allow and verify the same endpoints again.
6. Remove only the probe's temporary rule. Stop the echo servers.

Before build 6, all four IPv4/IPv6 TCP/UDP tests could echo successfully even with an acknowledged Block rule. This is the regression these fixtures detect. They exercise the installed kernel/provider path rather than just inspecting rule objects.

The fixtures send no external traffic and do not change another app's rules, system proxy settings, or security agents.
