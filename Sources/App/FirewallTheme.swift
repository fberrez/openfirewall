import SwiftUI

/// Small, adaptive palette. Values are OKLCH (D65), converted to sRGB below.
enum FirewallTheme {
    static let surface = adaptive((0.975, 0.009, 145), (0.12, 0.008, 145))
    static let sidebar = adaptive((0.94, 0.015, 145), (0.15, 0.012, 145))
    static let panel = adaptive((0.955, 0.014, 145), (0.18, 0.018, 145))
    static let line = adaptive((0.64, 0.065, 145), (0.49, 0.095, 145))
    static let ink = adaptive((0.27, 0.055, 145), (0.88, 0.155, 145))
    static let secondary = adaptive((0.43, 0.055, 145), (0.68, 0.075, 145))
    static let accent = adaptive((0.40, 0.125, 145), (0.86, 0.22, 141))
    static let onAccent = adaptive((0.975, 0.009, 145), (0.13, 0.016, 145))
    static let selection = adaptive((0.88, 0.045, 145), (0.24, 0.055, 145))
    static let allow = adaptive((0.40, 0.105, 145), (0.82, 0.17, 145))
    static let block = adaptive((0.48, 0.16, 25), (0.75, 0.158, 25))
    static let warning = adaptive((0.45, 0.095, 80), (0.80, 0.13, 80))

    private typealias OKLCH = (Double, Double, Double)
    private static func adaptive(_ light: OKLCH, _ dark: OKLCH) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            rgb(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }
    private static func rgb(_ color: OKLCH) -> NSColor {
        let (lightness, chroma, hue) = color
        let a = chroma * cos(hue * .pi / 180)
        let b = chroma * sin(hue * .pi / 180)
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        func channel(_ value: Double) -> CGFloat {
            let encoded = value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
            return CGFloat(min(1, max(0, encoded)))
        }
        return NSColor(srgbRed: channel(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                       green: channel(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                       blue: channel(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s), alpha: 1)
    }
}

enum FirewallAppearance: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var title: String { self == .dark ? "Terminal" : self == .light ? "Daylight" : "System" }
    var scheme: ColorScheme? {
        switch self { case .light: .light; case .dark: .dark; case .system: nil }
    }
}

/// Original pixel shield. No third-party artwork or font is bundled.
struct PixelShield: View {
    var size: CGFloat = 34
    var body: some View {
        Canvas { context, bounds in
            let pixels = [
                "    xxxx    ",
                "  xxxxxxxx  ",
                "xxxxxxxxxxxx",
                "xxxxxxxxxxxx",
                "xxxxxxxxxxxx",
                "xxxxxxxxxxxx",
                "xxxxxxxxxxxx",
                " xxxxxxxxxx ",
                " xxxxxxxxxx ",
                "  xxxxxxxx  ",
                "   xxxxxx   ",
                "    xxxx    ",
                "     xx     "
            ]
            let unit = min(bounds.width / 12, bounds.height / 13)
            for (y, row) in pixels.enumerated() {
                for (x, pixel) in row.enumerated() where pixel == "x" {
                    let rect = CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit, width: unit, height: unit)
                    context.fill(Path(rect), with: .color(x < 6 ? FirewallTheme.accent : FirewallTheme.accent.opacity(0.50)))
                }
            }
        }.frame(width: size * 12 / 13, height: size).accessibilityHidden(true)
    }
}

struct FirewallSeparator: View {
    var body: some View { Rectangle().fill(FirewallTheme.line).frame(height: 1).accessibilityHidden(true) }
}

struct FirewallSearchField: View {
    let prompt: String
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Text(">").foregroundStyle(FirewallTheme.accent).accessibilityHidden(true)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.system(size: 12, design: .monospaced)).focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(FirewallTheme.secondary)
                    .accessibilityLabel("Clear search")
            }
        }.padding(.horizontal, 11).padding(.vertical, 9)
            .background(FirewallTheme.panel)
            .overlay(Rectangle().strokeBorder(focused ? FirewallTheme.accent : FirewallTheme.line, lineWidth: focused ? 2 : 1))
    }
}

struct TerminalButtonStyle: ButtonStyle {
    var primary = false
    var destructive = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovered = false
    private var color: Color { destructive ? FirewallTheme.block : FirewallTheme.accent }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 13).frame(minHeight: 32)
            .foregroundStyle(primary || configuration.isPressed ? FirewallTheme.onAccent : color)
            .background(primary || configuration.isPressed ? color : hovered ? FirewallTheme.selection : FirewallTheme.panel)
            .overlay(Rectangle().strokeBorder(color.opacity(primary ? 1 : 0.65), lineWidth: 1))
            .overlay(Rectangle().strokeBorder(focused ? FirewallTheme.accent : .clear, lineWidth: 2).padding(-3))
            .opacity(enabled ? 1 : 0.4)
            .onHover { hovered = $0 }
    }
}

struct TerminalRowButtonStyle: ButtonStyle {
    @State private var hovered = false
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hovered || configuration.isPressed || focused ? FirewallTheme.selection : .clear)
            .overlay(Rectangle().strokeBorder(focused ? FirewallTheme.accent : .clear, lineWidth: 1))
            .onHover { hovered = $0 }
    }
}

/// Native buttons keep keyboard and accessibility activation; selection is explicit.
struct TerminalSegments<Value: Hashable>: View {
    let title: String
    let values: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    var destructive: (Value) -> Bool = { _ in false }
    var body: some View {
        HStack(spacing: 4) {
            ForEach(values, id: \.self) { value in
                Button { if selection != value { selection = value } } label: {
                    Text(label(value).uppercased()).frame(maxWidth: .infinity)
                }.buttonStyle(TerminalButtonStyle(primary: selection == value, destructive: selection == value && destructive(value)))
                    .accessibilityLabel("\(title): \(label(value))")
                    .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }.accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}
