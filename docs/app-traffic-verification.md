# Application traffic verification

Build 9, 2026-10-29. Local checks used macOS 26.2 on Apple Silicon. The installed filter was not replaced, enabled, disabled, or updated.

## Accounting checks

All 20 core tests passed, including 10 traffic-accounting tests. They cover statistics arriving after log eviction, closed connections, log clearing, duplicate and out-of-order reports, separate verified identities with identical names, accounting limits, overflow, baseline subtraction, new apps, UI restart, provider restart, numeric sorting, filtered groups, and old/new snapshot decoding. The Security.framework identity smoke test passed.

## Native UI checks

- Apps mode initially displayed Notes (1 MB), Safari (918 KB), Terminal (0 bytes), sorted by numeric RX descending.
- Expanding Notes displayed its six retained connections, also sorted by RX descending.
- Clicking RX reversed the order, then restored descending order.
- Searching for `wikipedia` retained four matching connections while app totals stayed 1 MB, 918 KB, and zero. Block showed only Terminal.
- Connections mode displayed individual records sorted by RX, including a closed sample flow.
- Clearing the preview log left the three application rows and their RX totals intact, with zero retained connections.
- The grouped table, primary actions, search, and decision controls remained usable at about 1000 points wide.
- The README screenshot contains sample data only.

The universal unsigned app and embedded extension built and passed bundle validation. Preview and core tests do not establish live accounting correctness or upgrade reliability. Build 9 needs isolated signed-device testing before distribution. The alpha.2 build 8 draft remains unchanged.
