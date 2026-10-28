# Terminal interface verification

Verified on 2026-10-28, macOS 26.2, Apple Silicon. Initial terminal interface checks used build 5. Build 7 removed redundant copy. The unreleased build 8 retains that interface. Alpha.1 was build 4.

## Build 7 simplification

- Removed page subtitles, sidebar tagline, module eyebrow, privacy slogans, repeated empty-state explanations, setup tutorial, and appearance subtitle.
- Kept filter state, rule acknowledgements, errors, identity paths, default-vs-app-rule labels, and the flow-tracking warning.
- Inspected Connections, Applications, Rules, Setup, and the app picker in the native unsigned preview.
- Command-1 through Command-4 and Command-N worked. Search with no matches showed `NO MATCHES`; Reset filters restored all 18 sample connections.
- Updated the README screenshot from the native preview. It contains sample data only.
- All 10 core tests and the identity smoke test passed.

## Checks performed

- Universal app and extension build succeeded for arm64 and x86_64.
- All 10 existing core tests passed.
- Connections, Applications, Rules, Setup, and the app picker were inspected in the running native app.
- Decision filters returned 6 blocked sample connections and 12 allowed sample connections.
- Searching for `wikipedia` returned 4 sample connections. A query without results showed an accurate empty state; Reset filters restored all 18 sample connections.
- Changing Notes to Block updated sample totals to 6 allowed and 12 blocked. Removing the new rule restored the default behavior.
- Adding TextEdit through the searchable installed-app picker created a preview rule. Preview changes did not modify the saved user policy.
- Command-1 through Command-4 switched pages. Command-N opened the app picker. Command-E opened the native export dialog, which was cancelled. Tab moved from search to the native table without trapping focus.
- Terminal and Daylight appearances were visually inspected. The Terminal appearance was restored.
- The window was resized to about 1000 points wide. Search, filters, primary actions, and the connection table remained usable.
- The screenshot in the README uses sample data only.

## Contrast

Computed from the theme's OKLCH values after sRGB conversion and gamut clipping. These are token checks, not a claim of a full accessibility certification.

| Terminal text pair | Contrast |
| --- | ---: |
| Primary text / main surface | 14.87:1 |
| Secondary text / main surface | 7.26:1 |
| Secondary text / sidebar | 7.03:1 |
| Secondary text / selection | 5.80:1 |
| Button text / selected Allow | 14.03:1 |
| Button text / selected Block | 8.32:1 |

Allow and Block also have distinct text and symbols. No motion effects were introduced. Full VoiceOver qualification and verification on older macOS versions remain outstanding.

## Upgrade qualification

Build 7 passed artifact signing/notarization checks, but replacement of the running build 6 failed: the new Mach listener reported `Operation not permitted`, the UI lost contact, and all four loopback echo attempts timed out. Build 6 was restored, and all four echo checks passed again. No build 7 release was published.

Build 8 versions the Mach service and handles XPC interruption. It must pass isolated upgrade testing before alpha.2 is published. The active user installation remains build 6. No further extension activation is authorized on this Mac. See [extension upgrades](extension-upgrades.md).
