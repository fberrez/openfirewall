import SwiftUI

@main
struct OpenFirewallApp: App {
    @StateObject private var model = FirewallModel()
    var body: some Scene {
        WindowGroup("OpenFirewall", id: "main") {
            FirewallWindow(model: model, setup: model.setup)
                .frame(minWidth: 980, minHeight: 650)
                .task { model.start() }
        }
        .defaultSize(width: 1190, height: 780)
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
}

struct FirewallWindow: View {
    @ObservedObject var model: FirewallModel
    @ObservedObject var setup: SystemSetup
    @State private var page: FirewallPage? = .connections
    @State private var search = ""
    @State private var decisionFilter = "All"
    private var filtered: [ConnectionRecord] {
        model.connections.filter {
            (decisionFilter == "All" || $0.action.title == decisionFilter) &&
            (search.isEmpty || [$0.application.name, $0.host, $0.application.path, $0.port].joined(separator: " ").localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 26)).foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OpenFirewall").font(.headline)
                        Text("Your apps. Your rules.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20)
                List(FirewallPage.allCases, selection: $page) { item in
                    Label(item.rawValue, systemImage: item.symbol).tag(item)
                }.listStyle(.sidebar)
                Divider().padding(.horizontal)
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.preview ? "Preview" : model.connected ? "Firewall on" : "Not connected", systemImage: "circle.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(model.preview ? .orange : model.connected ? .green : .secondary)
                    Text("Free and open source").font(.caption2).foregroundStyle(.secondary)
                    Text("MIT licensed · v0.1").font(.caption2).foregroundStyle(.tertiary)
                }.padding(20)
            }.navigationSplitViewColumnWidth(220)
        } detail: {
            VStack(spacing: 0) {
                if model.preview {
                    HStack {
                        Label("Preview · sample connections, no filtering", systemImage: "eye")
                        Spacer()
                        Button("Exit preview") { model.togglePreview() }
                    }.font(.callout).padding(12).background(.orange.opacity(0.12))
                }
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(page?.rawValue ?? "Connections").font(.system(size: 28, weight: .semibold))
                        Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if page == .rules || page == .applications {
                        Button { model.addApplication() } label: { Label("Add app", systemImage: "plus") }
                    } else if page == .connections {
                        Button { model.exportHistory() } label: { Label("Export", systemImage: "square.and.arrow.up") }.disabled(model.connections.isEmpty)
                    }
                }.padding(26)
                switch page {
                case .rules: ruleContent
                case .applications: applicationContent
                case .setup: setupContent
                default: connectionContent
                }
                Spacer(minLength: 0)
                Divider()
                HStack(spacing: 8) {
                    Circle().fill(model.connected ? Color.green : model.preview ? .orange : .gray).frame(width: 6, height: 6)
                    Text(model.updateMessage ?? model.status)
                    Spacer()
                    Text("Connection metadata only").foregroundStyle(.secondary)
                }.font(.caption).padding(.horizontal, 22).padding(.vertical, 12)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(.teal)
        .sheet(isPresented: $model.showingApplicationPicker) {
            InstalledApplicationPicker(onSelect: model.selectApplication, onBrowse: model.browseApplication)
        }
        .alert("OpenFirewall", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var subtitle: String {
        switch page {
        case .rules: "Decide which apps can connect. Changes also block tracked open connections."
        case .applications: "Apps observed by the filter, plus apps you added."
        case .setup: "Let macOS enable the network filter. You stay in control."
        default: "See where your apps connect and what the firewall allows."
        }
    }

    @ViewBuilder private var connectionContent: some View {
        if model.connections.isEmpty && !model.connected && !model.preview {
            VStack(spacing: 20) {
                Image(systemName: "network.badge.shield.half.filled").font(.system(size: 56, weight: .light)).foregroundStyle(.teal)
                Text("A clearer view of your connections").font(.title2.weight(.semibold))
                Text("Enable the firewall to see live connections.\nApps without a rule are allowed by default.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Set up firewall") { page = .setup }.buttonStyle(.borderedProminent)
                    Button("Explore preview") { model.togglePreview() }.buttonStyle(.bordered)
                }
                Text("No packet contents are stored or uploaded.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
        } else {
            HStack(spacing: 14) {
                metric("Shown", value: "\(model.connections.count)", symbol: "arrow.left.arrow.right")
                metric("Allowed", value: "\(model.connections.filter { $0.action == .allow }.count)", symbol: "checkmark.shield")
                metric("Blocked", value: "\(model.connections.filter { $0.action == .deny }.count)", symbol: "hand.raised")
                ActivityBars(records: model.connections).frame(maxWidth: .infinity)
            }.padding(.horizontal, 26).padding(.bottom, 20)
            HStack {
                TextField("Search apps or destinations", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 310)
                Spacer()
                Picker("Decision", selection: $decisionFilter) { ForEach(["All", "Allow", "Block"], id: \.self) { Text($0) } }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 210)
                Button { model.clearHistory() } label: { Image(systemName: "trash") }.help("Clear connection history")
            }.padding(.horizontal, 26).padding(.bottom, 12)
            Table(filtered) {
                TableColumn("Application") { record in
                    HStack(spacing: 8) { AppIcon(path: record.application.path, size: 24); Text(record.application.name).lineLimit(1) }
                        .padding(.vertical, 5)
                }.width(min: 130, ideal: 180)
                TableColumn("Destination") { record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.host).lineLimit(1)
                        Text("\(record.transport) · \(record.port.isEmpty ? "—" : record.port) · \(record.direction)").font(.caption2).foregroundStyle(.secondary)
                    }
                }.width(min: 150, ideal: 230)
                TableColumn("Decision") { record in DecisionBadge(action: record.action) }.width(80)
                TableColumn("Received") { record in Text(bytes(record.bytesIn)).monospacedDigit().foregroundStyle(.secondary) }.width(80)
                TableColumn("State") { record in Text(record.state.rawValue.capitalized).font(.caption).foregroundStyle(.secondary) }.width(65)
                TableColumn("") { record in
                    Menu {
                        Button("Allow this app") { model.setRule(.allow, application: record.application) }
                        Button("Block this app") { model.setRule(.deny, application: record.application) }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton)
                        .disabled(!record.application.canCreateRule).frame(width: 22)
                }.width(28)
            }
            HStack {
                Text("\(filtered.count) shown · latest 500 connections · bytes update about every 5 seconds")
                Spacer()
                if model.evicted > 0 { Text("\(model.evicted) older records removed") }
            }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 26).padding(.vertical, 10)
            if model.untracked > 0 {
                Text("Flow tracking limit reached. New connections still use your rules; some existing flows require reconnecting for a rule change.")
                    .font(.caption).foregroundStyle(.orange).padding(.horizontal, 26)
            }
        }
    }

    private var ruleContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apps without a rule").font(.headline)
                    Text("An explicit app rule takes priority.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Default action", selection: Binding(get: { model.policy.defaultAction }, set: model.setDefault)) {
                    ForEach(FirewallAction.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 160)
            }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 10))
            Text("APP RULES · \(model.policy.rules.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if model.policy.rules.isEmpty {
                ContentUnavailableView("No app rules yet", systemImage: "slider.horizontal.3", description: Text("Add an app, or create a rule from a connection."))
            } else {
                ScrollView { LazyVStack(spacing: 1) {
                    ForEach(model.policy.rules.sorted { $0.application.name.localizedStandardCompare($1.application.name) == .orderedAscending }) { rule in
                        appRuleRow(rule.application, action: rule.action, removable: true)
                    }
                }}
            }
            Text("Allow applies to future connection attempts. A connection that was already dropped must reconnect.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 26)
    }

    private var applicationContent: some View {
        let known = Dictionary((model.connections.map(\.application) + model.policy.rules.map(\.application)).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ScrollView { LazyVStack(spacing: 1) {
            if known.isEmpty { ContentUnavailableView("No apps observed", systemImage: "square.grid.2x2", description: Text("Apps appear when they connect. You can also add one now.")) }
            ForEach(known.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { app in
                appRuleRow(app, action: model.explicitAction(app.id) ?? model.policy.defaultAction, removable: false)
            }
        }.padding(.horizontal, 26) }
    }

    private func appRuleRow(_ app: ApplicationIdentity, action: FirewallAction, removable: Bool) -> some View {
        HStack(spacing: 12) {
            AppIcon(path: app.path, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(app.name).font(.headline); if !app.isVerifiedSigner { Text("Pinned build").font(.caption2).foregroundStyle(.secondary) } }
                Text(app.path.isEmpty ? "Identity unavailable" : app.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(app.id)
            }
            Spacer()
            Picker("Rule for \(app.name)", selection: Binding(get: { action }, set: { model.setRule($0, application: app) })) {
                ForEach(FirewallAction.allCases, id: \.self) { Text($0.title).tag($0) }
            }.labelsHidden().pickerStyle(.segmented).frame(width: 150).disabled(!app.canCreateRule)
            if removable { Button { model.removeRule(app.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("Remove rule") }
        }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private var setupContent: some View {
        ScrollView { VStack(alignment: .leading, spacing: 22) {
            Label(model.connected ? "Firewall is running" : "Enable connection filtering", systemImage: model.connected ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                .font(.title2.weight(.semibold)).foregroundStyle(.teal)
            Text("OpenFirewall uses a macOS network extension. macOS asks you to approve it before it can monitor or block connections.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 16) {
                setupStep("1", title: "Use a signed app", detail: "Build with your Apple signing team and move OpenFirewall to Applications. See the included README for setup.")
                setupStep("2", title: "Approve the network extension", detail: "Choose Enable firewall, then approve OpenFirewall in System Settings if requested.")
                setupStep("3", title: "Choose your app rules", detail: "Connections are allowed by default. Add Block rules for apps you want to keep offline.")
            }.padding(22).background(.background, in: RoundedRectangle(cornerRadius: 10))
            Text(setup.message).font(.callout).textSelection(.enabled)
            HStack {
                if setup.enabled {
                    Button("Disable firewall") { model.disable() }.disabled(setup.busy || model.preview)
                } else {
                    Button("Enable firewall") { model.enable() }.buttonStyle(.borderedProminent).disabled(setup.busy || model.preview)
                }
                if setup.busy { ProgressView().controlSize(.small) }
                Button("Open System Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!) }
                if !model.connected && !setup.enabled { Button(model.preview ? "Exit preview" : "Explore preview") { model.togglePreview() } }
            }
            Divider()
            Text("Private by design").font(.headline)
            Text("Connection history stays in the filter's memory. Rules are saved locally. Nothing is uploaded. Closing this window leaves an enabled firewall running.").font(.callout).foregroundStyle(.secondary)
            Text("This first version uses process identity and connection metadata. Hostnames appear only when macOS supplies them; DNS and ECH inspection are outside this version.").font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 26).padding(.bottom, 26).frame(maxWidth: 760, alignment: .leading) }
    }
    private func setupStep(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.headline).frame(width: 28, height: 28).background(.teal.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(detail).font(.callout).foregroundStyle(.secondary) }
        }
    }
    private func metric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
        }.frame(width: 105, alignment: .leading).padding(15).background(.background, in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct DecisionBadge: View {
    var action: FirewallAction
    var body: some View {
        Text(action == .allow ? "Allowed" : "Blocked").font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(action == .allow ? Color.teal : .red)
            .background((action == .allow ? Color.teal : .red).opacity(0.09), in: Capsule())
    }
}

private struct AppIcon: View {
    var path: String
    var size: CGFloat
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: iconPath)).resizable().interpolation(.high).frame(width: size, height: size)
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
        let counts = (0..<30).map { bin in records.filter { Int(now.timeIntervalSince($0.startedAt) / 2) == 29 - bin }.count }
        let peak = max(1, counts.max() ?? 1)
        VStack(alignment: .leading, spacing: 10) {
            Text("CONNECTIONS · LAST MINUTE").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(counts.enumerated()), id: \.offset) { _, count in
                    RoundedRectangle(cornerRadius: 2).fill(Color.teal.opacity(count > 0 ? 0.7 : 0.12))
                        .frame(height: max(3, CGFloat(count) / CGFloat(peak) * 40))
                }
            }.frame(height: 40)
        }.padding(15).background(.background, in: RoundedRectangle(cornerRadius: 9))
    }
}

private func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .binary) }
