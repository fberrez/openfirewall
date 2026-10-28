import SwiftUI

struct InstalledApplicationPicker: View {
    var onSelect: (URL) -> Void
    var onBrowse: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var apps: [InstalledApplication] = []
    @State private var loading = true

    private var matching: [InstalledApplication] {
        apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.url.path.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                PixelShield(size: 30)
                Text("> ADD APP").font(.system(size: 24, weight: .semibold, design: .monospaced)).tracking(-0.5)
            }
            Text("Choose an app to manage its internet access.").font(.system(size: 12, design: .monospaced)).foregroundStyle(FirewallTheme.secondary)
            FirewallSearchField(prompt: "Search installed apps", text: $search)
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(matching) { app in
                            Button { onSelect(app.url) } label: {
                                HStack(spacing: 12) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                        .resizable().frame(width: 30, height: 30)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(app.name).font(.system(size: 13, weight: .medium, design: .monospaced))
                                        Text(app.url.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(FirewallTheme.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle").foregroundStyle(FirewallTheme.accent)
                                }.padding(10).contentShape(Rectangle())
                            }.buttonStyle(TerminalRowButtonStyle())
                        }
                        if matching.isEmpty {
                            ContentUnavailableView.search(text: search)
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            FirewallSeparator()
            HStack {
                Button("BROWSE…", action: onBrowse)
                Spacer()
                Button("CANCEL") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 600, height: 520)
            .foregroundStyle(FirewallTheme.ink).background(FirewallTheme.surface).tint(FirewallTheme.accent)
            .buttonStyle(TerminalButtonStyle())
            .task {
                apps = await Task.detached(priority: .userInitiated) { InstalledApplication.scan() }.value
                loading = false
            }
    }
}

private struct InstalledApplication: Identifiable, Sendable {
    let url: URL
    let name: String
    var id: String { url.path }

    static func scan() -> [InstalledApplication] {
        let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true),
                     URL(fileURLWithPath: "/System/Applications", isDirectory: true),
                     FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
        var discovered: [String: InstalledApplication] = [:]
        for root in roots {
            guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in iterator {
                if url.pathExtension.lowercased() == "app" {
                    let bundle = Bundle(url: url)
                    let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                        ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                        ?? url.deletingPathExtension().lastPathComponent
                    discovered[url.path] = InstalledApplication(url: url, name: name)
                    iterator.skipDescendants()
                } else if iterator.level > 2 { iterator.skipDescendants() }
            }
        }
        return discovered.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
