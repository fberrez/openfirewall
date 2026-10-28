import SwiftUI

@main
struct OpenFirewallApp: App {
    @StateObject private var model = FirewallModel()
    @AppStorage("appearance") private var appearance = FirewallAppearance.dark.rawValue
    var body: some Scene {
        WindowGroup("OpenFirewall", id: "main") {
            FirewallWindow(model: model, setup: model.setup)
                .frame(minWidth: 1000, minHeight: 660)
                .preferredColorScheme((FirewallAppearance(rawValue: appearance) ?? .dark).scheme)
                .task { model.start() }
        }
        .defaultSize(width: 1200, height: 790)
        .windowStyle(.hiddenTitleBar)
        .commands { CommandGroup(replacing: .newItem) {} }
        MenuBarExtra("OpenFirewall", systemImage: "shield.lefthalf.filled") {
            FirewallMenu(model: model)
        }
    }
}

private struct FirewallMenu: View {
    @ObservedObject var model: FirewallModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.preview ? "Preview mode" : model.status)
        Button("Open OpenFirewall") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        if model.connected { Button("Disable firewall") { model.disable() } }
        Button("Quit OpenFirewall") { NSApp.terminate(nil) }
    }
}

private enum FirewallPage: String, CaseIterable, Identifiable {
    case connections = "Connections", applications = "Applications", rules = "Rules", setup = "Setup"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .connections: "network"; case .applications: "square.grid.2x2"; case .rules: "slider.horizontal.3"; case .setup: "gearshape" }
    }
    var shortcut: KeyEquivalent {
        switch self { case .connections: "1"; case .applications: "2"; case .rules: "3"; case .setup: "4" }
    }
}

struct FirewallWindow: View {
    @ObservedObject var model: FirewallModel
    @ObservedObject var setup: SystemSetup
    @AppStorage("appearance") private var appearance = FirewallAppearance.dark.rawValue
    @State private var page: FirewallPage = .connections
    @State private var search = ""
    @State private var decisionFilter = "All"
    private var filtered: [ConnectionRecord] {
        model.connections.filter {
            (decisionFilter == "All" || $0.action.title == decisionFilter) &&
            (search.isEmpty || [$0.application.name, $0.host, $0.application.path, $0.port].joined(separator: " ").localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 224)
            Rectangle().fill(FirewallTheme.line).frame(width: 1).accessibilityHidden(true)
            VStack(spacing: 0) {
                if model.preview { previewBanner }
                pageHeader
                switch page {
                case .connections: connectionContent
                case .applications: applicationContent
                case .rules: ruleContent
                case .setup: setupContent
                }
                Spacer(minLength: 0)
                statusFooter
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(FirewallTheme.surface)
        }
        .foregroundStyle(FirewallTheme.ink)
        .font(.system(size: 12, design: .monospaced))
        .buttonStyle(TerminalButtonStyle())
        .tint(FirewallTheme.accent)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .sheet(isPresented: $model.showingApplicationPicker) {
            InstalledApplicationPicker(onSelect: model.selectApplication, onBrowse: model.browseApplication)
        }
        .alert("OpenFirewall", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("[>_]").font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(FirewallTheme.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("OPENFIREWALL").font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(0.6)
                    Text("LOCAL NETWORK CONTROL").font(.system(size: 8, design: .monospaced)).foregroundStyle(FirewallTheme.secondary)
                }
            }.padding(.horizontal, 18).padding(.top, 28).padding(.bottom, 32)
            FirewallSectionLabel(title: "// MODULES").padding(.horizontal, 24).padding(.bottom, 12)
            VStack(spacing: 5) {
                ForEach(FirewallPage.allCases) { item in
                    Button { page = item } label: {
                        HStack(spacing: 11) {
                            Text("#").foregroundStyle(FirewallTheme.accent).frame(width: 14)
                            Text(item.rawValue.uppercased()).font(.system(size: 11, weight: page == item ? .semibold : .medium, design: .monospaced))
                            Spacer(minLength: 0)
                            if page == item { Text("<").foregroundStyle(FirewallTheme.accent) }
                        }.padding(.horizontal, 12).frame(height: 39).contentShape(Rectangle())
                    }
                    .buttonStyle(SidebarButtonStyle(selected: page == item))
                    .keyboardShortcut(item.shortcut, modifiers: .command)
                    .accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }.padding(.horizontal, 12)
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                FirewallSeparator()
                HStack(spacing: 8) {
                    Rectangle().fill(statusColor).frame(width: 7, height: 7)
                    Text(model.preview ? "[PREVIEW]" : model.connected ? "[FILTER ONLINE]" : "[FILTER OFFLINE]")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }.padding(.top, 6)
                Text(model.preview ? "Sample data. No filtering." : model.connected ? "Your app rules are active." : "Open Setup to get connected.")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(FirewallTheme.secondary)
                Text("OPEN SOURCE / MIT\nv\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
                    .font(.system(size: 10, design: .monospaced)).lineSpacing(5).foregroundStyle(FirewallTheme.secondary).padding(.top, 10)
            }.padding(22)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(FirewallTheme.sidebar)
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Text(">").foregroundStyle(FirewallTheme.accent).accessibilityHidden(true)
                    Text(page == .connections ? "CONNECTION LOG" : page.rawValue.uppercased())
                }.font(.system(size: 24, weight: .semibold, design: .monospaced)).tracking(0.6)
                Text(subtitle).font(.system(size: 12, design: .monospaced)).foregroundStyle(FirewallTheme.secondary)
            }
            Spacer(minLength: 12)
            if page == .connections {
                Button { model.exportHistory() } label: { Label("EXPORT", systemImage: "square.and.arrow.up") }
                    .keyboardShortcut("e", modifiers: .command).disabled(model.connections.isEmpty).controlSize(.large)
            }
            if page != .setup {
                Button { model.addApplication() } label: { Label("ADD APP", systemImage: "plus") }
                    .buttonStyle(TerminalButtonStyle(primary: true)).controlSize(.large)
                    .keyboardShortcut("n", modifiers: .command)
            }
        }.padding(.horizontal, 28).padding(.top, 25).padding(.bottom, 28)
    }

    private var subtitle: String {
        switch page {
        case .connections: "Inspect destinations. Trace decisions. Control access."
        case .applications: "Manage internet access, one app at a time."
        case .rules: "Explicit app rules override the default policy."
        case .setup: "Configure the network filter and interface."
        }
    }

    private var statusColor: Color { model.preview ? FirewallTheme.accent : model.connected ? FirewallTheme.allow : FirewallTheme.secondary }

    private var previewBanner: some View {
        HStack {
            Label("Preview · sample connections, no filtering", systemImage: "eye")
            Spacer()
            Button("EXIT PREVIEW") { model.togglePreview() }
        }.font(.system(size: 11, design: .monospaced)).padding(.horizontal, 28).padding(.vertical, 10).background(FirewallTheme.selection)
    }

    private var statusFooter: some View {
        VStack(spacing: 0) {
            FirewallSeparator()
            HStack(spacing: 7) {
                Rectangle().fill(statusColor).frame(width: 5, height: 5)
                Text(model.updateMessage ?? model.status).lineLimit(1)
                Spacer()
                Text("LOCAL ONLY // NO TELEMETRY").foregroundStyle(FirewallTheme.secondary)
            }.font(.system(size: 10, design: .monospaced)).padding(.horizontal, 28).padding(.vertical, 12)
        }
    }

    @ViewBuilder private var connectionContent: some View {
        if model.connections.isEmpty && !model.connected && !model.preview {
            VStack(spacing: 17) {
                PixelShield(size: 78).padding(.bottom, 12)
                Text("FILTER OFFLINE").font(.system(size: 24, weight: .semibold, design: .monospaced)).tracking(1)
                Text("Enable the firewall to see live connections\nand choose which apps can access the internet.")
                    .font(.system(size: 13, design: .monospaced)).lineSpacing(4).multilineTextAlignment(.center).foregroundStyle(FirewallTheme.secondary)
                HStack(spacing: 12) {
                    Button("Set up firewall") { page = .setup }.buttonStyle(TerminalButtonStyle(primary: true))
                    Button("Explore preview") { model.togglePreview() }
                }.controlSize(.large).padding(.top, 7)
                Text("[NO ACCOUNT] [NO SUBSCRIPTION] [LOCAL ONLY]").font(.system(size: 10, design: .monospaced)).foregroundStyle(FirewallTheme.secondary).padding(.top, 10)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
        } else {
            connectionSummary
            HStack(spacing: 14) {
                FirewallSearchField(prompt: "Search apps or destinations", text: $search).frame(maxWidth: 350)
                Spacer(minLength: 8)
                TerminalSegments(title: "Decision", values: ["All", "Allow", "Block"], selection: $decisionFilter, label: { $0 }, destructive: { $0 == "Block" })
                    .frame(width: 230)
                Button { model.clearHistory() } label: { Label("Clear history", systemImage: "trash") }
                    .labelStyle(.iconOnly).help("Clear connection history").disabled(model.connections.isEmpty)
            }.padding(.horizontal, 28).padding(.vertical, 18)
            connectionTable
            HStack {
                Text("\(filtered.count) shown · latest 500 connections")
                Spacer()
                Text(model.evicted > 0 ? "\(model.evicted) older records removed" : "Byte counts update every 5 seconds")
            }.font(.system(size: 10, design: .monospaced)).foregroundStyle(FirewallTheme.secondary).padding(.horizontal, 28).padding(.vertical, 12)
            if model.untracked > 0 {
                Label("Tracking limit reached. New connections still use your rules. Some open connections must reconnect for rule changes.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(FirewallTheme.warning).padding(.horizontal, 28).padding(.bottom, 12)
            }
        }
    }

    private var connectionSummary: some View {
        VStack(spacing: 18) {
            HStack(spacing: 28) {
                summaryCount(model.connections.count, title: "Connections", color: FirewallTheme.ink)
                summaryCount(model.connections.filter { $0.action == .allow }.count, title: "Allowed", color: FirewallTheme.allow)
                summaryCount(model.connections.filter { $0.action == .deny }.count, title: "Blocked", color: FirewallTheme.block)
                Spacer(minLength: 12)
                ActivityBars(records: model.connections).frame(width: 210)
            }
            FirewallSeparator()
        }.padding(.horizontal, 28)
    }

    private func summaryCount(_ count: Int, title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(count.formatted()).font(.system(size: 24, weight: .medium, design: .monospaced)).monospacedDigit().foregroundStyle(color)
            Text(title).font(.system(size: 11, design: .monospaced)).foregroundStyle(FirewallTheme.secondary)
        }.accessibilityElement(children: .combine)
    }

    private var connectionTable: some View {
        Table(filtered) {
            TableColumn("APPLICATION") { record in
                HStack(spacing: 10) {
                    AppIcon(path: record.application.path, size: 26)
                    Text(record.application.name).font(.system(size: 12, weight: .medium, design: .monospaced)).lineLimit(1)
                }.padding(.vertical, 8)
            }.width(min: 135, ideal: 180)
            TableColumn("DESTINATION") { record in
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.host).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                    Text("\(record.transport) · \(record.port.isEmpty ? "—" : record.port) · \(record.direction)")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(FirewallTheme.secondary)
                }
            }.width(min: 140, ideal: 240)
            TableColumn("DECISION") { record in DecisionBadge(action: record.action) }.width(90)
            TableColumn("RX") { record in Text(bytes(record.bytesIn)).font(.system(size: 11, design: .monospaced)).monospacedDigit().foregroundStyle(FirewallTheme.secondary) }.width(65)
            TableColumn("STATE") { record in Text(record.state.rawValue.uppercased()).font(.system(size: 10, design: .monospaced)).foregroundStyle(FirewallTheme.secondary) }.width(58)
            TableColumn("") { record in
                Menu {
                    Button("Allow this app") { model.setRule(.allow, application: record.application) }
                    Button("Block this app") { model.setRule(.deny, application: record.application) }
                } label: { Text("⋯").font(.system(size: 15, design: .monospaced)) }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .accessibilityLabel("Rule for \(record.application.name)")
                    .disabled(!record.application.canCreateRule).frame(width: 22)
            }.width(28)
        }.alternatingRowBackgrounds(.disabled).tableStyle(.inset).font(.system(size: 10, design: .monospaced))
            .scrollContentBackground(.hidden).background(FirewallTheme.surface)
            .overlay { if filtered.isEmpty { ContentUnavailableView.search(text: search).allowsHitTesting(false) } }
    }

    private var ruleContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 20) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 24, weight: .light, design: .monospaced)).foregroundStyle(FirewallTheme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Apps without a rule").font(.system(size: 14, weight: .semibold, design: .monospaced))
                    Text("An app’s own rule always takes priority.").font(.system(size: 12, design: .monospaced)).foregroundStyle(FirewallTheme.secondary)
                }
                Spacer()
                TerminalSegments(title: "Default action", values: FirewallAction.allCases,
                    selection: Binding(get: { model.policy.defaultAction }, set: model.setDefault), label: { $0.title }, destructive: { $0 == .deny }).frame(width: 180)
            }.padding(20).background(FirewallTheme.panel).overlay(Rectangle().strokeBorder(FirewallTheme.line, lineWidth: 1))
            HStack {
                FirewallSectionLabel(title: "APP RULES")
                Text("\(model.policy.rules.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(FirewallTheme.secondary)
            }.padding(.top, 4)
            if model.policy.rules.isEmpty {
                ContentUnavailableView {
                    Label("Make your first rule", systemImage: "slider.horizontal.3")
                } description: { Text("Choose an app and decide whether it can connect.") }
                actions: { Button("Add app") { model.addApplication() } }
            } else {
                ScrollView { LazyVStack(spacing: 0) {
                    ForEach(model.policy.rules.sorted { $0.application.name.localizedStandardCompare($1.application.name) == .orderedAscending }) { rule in
                        appRuleRow(rule.application, action: rule.action, removable: true)
                        FirewallSeparator()
                    }
                }}
            }
            Label("Blocked connections must reconnect after you change a rule to Allow.", systemImage: "info.circle")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(FirewallTheme.secondary).padding(.bottom, 20)
        }.padding(.horizontal, 28)
    }

    private var applicationContent: some View {
        let known = Dictionary((model.connections.map(\.application) + model.policy.rules.map(\.application)).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ScrollView { LazyVStack(alignment: .leading, spacing: 0) {
            HStack {
                FirewallSectionLabel(title: "OBSERVED & ADDED")
                Spacer()
                Text("\(known.count) apps").font(.system(size: 11, design: .monospaced)).foregroundStyle(FirewallTheme.secondary)
            }.padding(.bottom, 15)
            FirewallSeparator()
            if known.isEmpty {
                ContentUnavailableView {
                    Label("Choose an app to get started", systemImage: "square.grid.2x2")
                } description: { Text("Apps also appear here when the firewall observes a connection.") }
                actions: { Button("Add app") { model.addApplication() } }
            }
            ForEach(known.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { app in
                appRuleRow(app, action: model.explicitAction(app.id) ?? model.policy.defaultAction, removable: false)
                FirewallSeparator()
            }
        }.padding(.horizontal, 28).padding(.bottom, 24) }
    }

    private func appRuleRow(_ app: ApplicationIdentity, action: FirewallAction, removable: Bool) -> some View {
        HStack(spacing: 13) {
            AppIcon(path: app.path, size: 36)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(app.name).font(.system(size: 13, weight: .semibold, design: .monospaced))
                    if !app.isVerifiedSigner { Text("Pinned build").font(.system(size: 10, design: .monospaced)).foregroundStyle(FirewallTheme.secondary) }
                }
                Text(app.path.isEmpty ? "Identity unavailable" : app.path).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(FirewallTheme.secondary).lineLimit(1).truncationMode(.middle).help(app.id)
            }
            Spacer(minLength: 12)
            if !removable {
                Text(model.explicitAction(app.id) == nil ? "Default" : "App rule")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(FirewallTheme.secondary)
            }
            TerminalSegments(title: "Rule for \(app.name)", values: FirewallAction.allCases,
                selection: Binding(get: { action }, set: { model.setRule($0, application: app) }), label: { $0.title }, destructive: { $0 == .deny })
                .frame(width: 180).disabled(!app.canCreateRule)
            if removable {
                Button { model.removeRule(app.id) } label: { Label("Remove rule for \(app.name)", systemImage: "minus.circle") }
                    .labelStyle(.iconOnly).help("Remove rule")
            }
        }.padding(.vertical, 18).padding(.horizontal, 2)
    }

    private var setupContent: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 24) {
                PixelShield(size: 66)
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.connected ? "FILTER ONLINE" : "INITIALIZE FILTER")
                        .font(.system(size: 23, weight: .semibold, design: .monospaced)).tracking(-0.5)
                    Text(model.connected ? "OpenFirewall is filtering connections on this Mac." : "macOS needs your approval before OpenFirewall can filter connections.")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(FirewallTheme.secondary)
                }
                Spacer(minLength: 0)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(FirewallTheme.sidebar)
                .overlay(Rectangle().strokeBorder(FirewallTheme.line, lineWidth: 1))
            VStack(alignment: .leading, spacing: 22) {
                setupStep("01", title: "Keep it in Applications", detail: "Move OpenFirewall to Applications and open it from there.")
                setupStep("02", title: "Give macOS the go-ahead", detail: "Enable the firewall below. Approve the extension and network filter when macOS asks.")
                setupStep("03", title: "Make the rules yours", detail: "Apps are allowed by default. Add a Block rule to keep an app offline.")
            }.padding(.vertical, 4)
            FirewallSeparator()
            Text(setup.message).font(.system(size: 12, design: .monospaced)).foregroundStyle(FirewallTheme.secondary).textSelection(.enabled)
            HStack(spacing: 12) {
                if setup.enabled {
                    Button("Update firewall") { model.enable() }.help("Install the network extension included with this version of OpenFirewall.")
                        .disabled(setup.busy || model.preview)
                    Button("Disable firewall") { model.disable() }.disabled(setup.busy || model.preview)
                } else {
                    Button("Enable firewall") { model.enable() }.buttonStyle(TerminalButtonStyle(primary: true)).disabled(setup.busy || model.preview)
                }
                if setup.busy { ProgressView().controlSize(.small) }
                Button("System Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!) }
                if !model.connected && !setup.enabled { Button(model.preview ? "Exit preview" : "Explore preview") { model.togglePreview() } }
            }.controlSize(.large)
            FirewallSeparator()
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Appearance").font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("Terminal is the default theme.").font(.system(size: 11, design: .monospaced)).foregroundStyle(FirewallTheme.secondary)
                }
                Spacer()
                TerminalSegments(title: "Appearance", values: FirewallAppearance.allCases.map(\.rawValue), selection: $appearance,
                    label: { FirewallAppearance(rawValue: $0)?.title ?? $0 }).frame(width: 300)
            }
            FirewallSeparator()
            VStack(alignment: .leading, spacing: 8) {
                Label("Your data stays here", systemImage: "internaldrive").font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text("Rules are saved on this Mac. Recent connections stay in the filter’s memory. Nothing is uploaded. The firewall keeps running when you close this window.")
                    .font(.system(size: 12, design: .monospaced)).lineSpacing(3).foregroundStyle(FirewallTheme.secondary)
                Text("Hostnames appear when macOS supplies them. This version does not inspect DNS, TLS, or ECH.")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(FirewallTheme.secondary)
            }
        }.padding(.horizontal, 28).padding(.bottom, 28).frame(maxWidth: 840, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading) }
    }

    private func setupStep(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text("[\(number)]").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(FirewallTheme.accent).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text(detail).font(.system(size: 12, design: .monospaced)).lineSpacing(3).foregroundStyle(FirewallTheme.secondary)
            }
        }
    }
}

private struct SidebarButtonStyle: ButtonStyle {
    let selected: Bool
    @State private var hovered = false
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? FirewallTheme.ink : FirewallTheme.secondary)
            .background(selected || hovered || configuration.isPressed ? FirewallTheme.selection : .clear)
            .overlay(Rectangle().strokeBorder(focused ? FirewallTheme.accent : selected ? FirewallTheme.line : .clear, lineWidth: focused ? 2 : 1))
            .onHover { hovered = $0 }
    }
}

private struct DecisionBadge: View {
    var action: FirewallAction
    var body: some View {
        Label(action == .allow ? "ALLOW" : "BLOCK", systemImage: action == .allow ? "checkmark" : "xmark")
            .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(action == .allow ? FirewallTheme.allow : FirewallTheme.block)
    }
}

private struct AppIcon: View {
    var path: String
    var size: CGFloat
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: iconPath)).resizable().interpolation(.high).frame(width: size, height: size).accessibilityHidden(true)
    }
    private var iconPath: String {
        if let range = path.range(of: ".app/") { return String(path[..<range.upperBound].dropLast()) }
        return path
    }
}

private struct ActivityBars: View {
    var records: [ConnectionRecord]
    var body: some View {
        let now = Date()
        let counts = records.reduce(into: Array(repeating: 0, count: 30)) { bins, record in
            let age = now.timeIntervalSince(record.startedAt)
            if age >= 0 && age < 60 { bins[29 - Int(age / 2)] += 1 }
        }
        let peak = max(1, counts.max() ?? 1)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LAST MINUTE").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(0.7)
                Spacer()
                Text("60s").font(.system(size: 9, design: .monospaced))
            }.foregroundStyle(FirewallTheme.secondary)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(counts.enumerated()), id: \.offset) { _, count in
                    Rectangle().fill(count > 0 ? FirewallTheme.accent.opacity(0.75) : FirewallTheme.line)
                        .frame(height: max(2, CGFloat(count) / CGFloat(peak) * 28))
                }
            }.frame(height: 28)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(counts.reduce(0, +)) connections in the last minute")
    }
}

private func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .binary) }
