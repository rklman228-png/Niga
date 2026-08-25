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
                        ContainerBrowserView(url: URL(fileURLWithPath: item.path, isDirectory: true))
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

            Section("Research target") {
                Text("If direct FrontBoard scene creation is entitlement-gated after sideload signing, this explorer is the fallback: find SpringBoard/FrontBoard/scene persistence inside Data/System or Shared/SystemGroup, snapshot it, change one native window action, then diff the files. That can reveal a writable state path for per-app geometry/orientation without pretending the whole phone is an iPad.")
                    .font(.footnote)
            }
        }
        .navigationTitle("System State")
    }
}
