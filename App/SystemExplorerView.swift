import SwiftUI

struct SystemExplorerView: View {
    @StateObject private var scanner = SystemContainerScanner()
    @State private var selectedRoot: SystemContainerRoot = .dataSystem

    var body: some View {
        List {
            Section("Scanner") {
                Picker("Root", selection: $selectedRoot) {
                    ForEach(SystemContainerRoot.allCases) { root in
                        Text(root.title).tag(root)
                    }
                }
                Button("Scan accessible system containers") {
                    scanner.scan(root: selectedRoot)
                }
                TextField("Filter: springboard, scene, frontboard…", text: $scanner.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text(scanner.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Containers") {
                ForEach(scanner.filteredItems) { item in
                    NavigationLink {
                        SystemContainerDetailView(item: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.identifier)
                            Text(item.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }

            Section("Why this exists") {
                Text("If direct FrontBoard control is entitlement-gated after sideload signing, this is the fallback path: mine writable Data/System and Shared/SystemGroup containers for SpringBoard / FrontBoard / scene persistence, then compare state before and after a native window action.")
                    .font(.footnote)
            }
        }
        .navigationTitle("System State")
    }
}

struct SystemContainerDetailView: View {
    let item: SystemContainerItem
    @StateObject private var miner = SceneStateMiner()

    var body: some View {
        List {
            Section("Container") {
                Text(item.identifier)
                Text(item.path)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                NavigationLink("Browse files") {
                    ContainerBrowserView(url: URL(fileURLWithPath: item.path, isDirectory: true))
                }
            }

            Section("Scene-state miner") {
                Button(miner.running ? "Scanning…" : "Find window / scene state") {
                    miner.scan(containerPath: item.path)
                }
                .disabled(miner.running)
                Text(miner.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Candidates") {
                ForEach(miner.hits) { hit in
                    NavigationLink {
                        SceneStateHitView(hit: hit)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(URL(fileURLWithPath: hit.path).lastPathComponent)
                            Text(hit.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(hit.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .navigationTitle(item.identifier)
    }
}

struct SceneStateHitView: View {
    let hit: SceneStateHit

    var body: some View {
        List {
            Section("Path") {
                Text(hit.path).font(.caption2.monospaced()).textSelection(.enabled)
                Text(hit.reason)
            }
            if !hit.snippet.isEmpty {
                Section("Preview") {
                    Text(hit.snippet)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }
            }
            Section {
                NavigationLink("Open containing directory") {
                    ContainerBrowserView(url: URL(fileURLWithPath: hit.path).deletingLastPathComponent())
                }
            }
        }
        .navigationTitle("State candidate")
    }
}
