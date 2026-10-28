# Terminal interface verification

Verified on 2026-10-28, macOS 26.2, Apple Silicon. This is a presentation update, build 5. The public alpha.1 release remains build 4.

## Checks performed

- Universal app and extension build succeeded for arm64 and x86_64.
- All 10 existing core tests passed.
- Connections, Applications, Rules, Setup, and the app picker were inspected in the running native app.
- Decision filters returned 6 blocked sample connections and 12 allowed sample connections.
- Searching for `wikipedia` returned 4 sample connections.
- Changing Notes to Block updated sample totals to 6 allowed and 12 blocked. Removing the new rule restored the default behavior.
- Adding TextEdit through the searchable installed-app picker created a preview rule. Preview changes did not modify the saved user policy.
- Command-1 through Command-4 switched pages. Command-N opened the app picker. Tab moved from search to the native table without trapping focus.
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
