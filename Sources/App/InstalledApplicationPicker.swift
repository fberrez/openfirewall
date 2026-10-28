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
            Text("Add an application").font(.title2.weight(.semibold))
            Text("Choose the app whose connections you want to manage.").foregroundStyle(.secondary)
            TextField("Search installed apps", text: $search).textFieldStyle(.roundedBorder)
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
                                        Text(app.name).font(.headline)
                                        Text(app.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle").foregroundStyle(.teal)
                                }.padding(10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        if matching.isEmpty {
                            ContentUnavailableView.search(text: search)
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Button("Choose another file…", action: onBrowse)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 600, height: 520)
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
