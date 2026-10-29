# OpenFirewall Design

## Direction

A native macOS network console inspired by https://app.nymchat.com/. The user explicitly requested a stronger hacker and nerd aesthetic. The physical scene is a laptop user inspecting connection decisions in a dim room; the interface should resemble a clear phosphor terminal, not a marketing dashboard.

## Color strategy

Dark by default. Green-tinted near-black surfaces, phosphor-green text and controls, thin green frames. A quieter green supports secondary text. Allow remains green; Block is red and also carries a distinct symbol and label. The terminal palette is deliberate, as requested, rather than inferred from the security category.

Tokens are authored in OKLCH and converted to sRGB in FirewallTheme.swift. A daylight counterpart and a system-following option are available in Setup. No pure black, decorative gradients, or glass panels.

## Typography

Native system monospaced type. 24-point uppercase page headings; 12-point connection data and body copy; 10–11-point supporting labels. Numbers align naturally. App names and destinations retain their actual case. Controls use concise uppercase labels. No eyebrows, subtitles, taglines, or repeated explanations. Show operational state and short errors; put reference material in the README or tooltips.

## Layout

A 224-point sidebar with module links and explicit filter status. The content area uses 28-point outer spacing. Keep connection summaries in one flat strip. Tables and app rules align in rows with separators. Rectangular controls use one-pixel frames, with no rounded cards.

## Components

- Original `[>_]` wordmark symbol, a static prompt before each page title, and an original pixel shield on setup and empty states.
- Module navigation with a full rectangular selection frame.
- Native buttons styled as terminal controls, with hover, press, disabled, and selected feedback.
- Search fields with a prompt glyph, clear action, and full border.
- Decision filters, app rules, and appearance choices share one button-group component. Selected choices carry an accessible selected state.
- The native macOS table preserves selection, scrolling, and accessibility. Alternate row fills are disabled.
- Connections offers Apps and Connections modes. App rows expand into retained connections. RX sorts numerically, highest first, and app totals cover the current OpenFirewall UI session independently of visible log rows.
- Decisions show ALLOW with a check and BLOCK with a cross. Color is supplementary.
- Add app is available on Connections, Applications, and Rules.
- Setup and empty states give accurate actions, not simulated terminal output.

## Motion and accessibility

No fake boot sequence, blinking cursor, animated scanlines, CRT distortion, or decorative motion. These would interfere with reading destinations and decisions. Preserve accessible native controls and keyboard activation. Use sufficient text contrast and explicit state labels. Test both appearances and the minimum window size.

## Scope

Keep signing identity, policy persistence, and enforcement unchanged. Traffic accounting uses metadata reports and does not inspect payloads. Test the separate unsigned UI preview; do not replace or activate the installed filter on the working Mac.
