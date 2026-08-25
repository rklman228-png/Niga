import Foundation
import Combine

enum SystemContainerRoot: String, CaseIterable, Identifiable, Hashable {
    case dataSystem = "/var/containers/Data/System"
    case sharedSystemGroup = "/var/containers/Shared/SystemGroup"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dataSystem: return "Data/System"
        case .sharedSystemGroup: return "Shared/SystemGroup"
        }
    }
}

struct SystemContainerItem: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let identifier: String
    let root: SystemContainerRoot
}

@MainActor
final class SystemContainerScanner: ObservableObject {
    @Published var items: [SystemContainerItem] = []
    @Published var status = "Not scanned"
    @Published var query = ""

    var filteredItems: [SystemContainerItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.identifier.localizedCaseInsensitiveContains(q) ||
            $0.path.localizedCaseInsensitiveContains(q)
        }
    }

    func scan(root: SystemContainerRoot, maxInode: Int64 = 800_000) {
        status = "Scanning \(root.title)…"
        DispatchQueue.global(qos: .userInitiated).async {
            let rootPath = root.rawValue
            guard let ptr = rootPath.withCString({ niga_list_children($0, maxInode) }) else {
                DispatchQueue.main.async { self.status = "Enumeration failed for \(root.title)" }
                return
            }
            let text = String(cString: ptr)
            niga_free_string(ptr)
            let paths = text.split(separator: "\n").map(String.init)
            var found: [SystemContainerItem] = []

            for path in paths {
                let dirHandle = path.withCString { niga_escape_path($0, false) }
                guard dirHandle >= 0 else { continue }
                defer { niga_release_path(dirHandle) }

                let meta = path + "/.com.apple.mobile_container_manager.metadata.plist"
                var identifier = URL(fileURLWithPath: path).lastPathComponent
                let metaHandle = meta.withCString { niga_escape_path($0, false) }
                if metaHandle >= 0 {
                    if let dict = NSDictionary(contentsOfFile: meta),
                       let value = dict["MCMMetadataIdentifier"] as? String,
                       !value.isEmpty {
                        identifier = value
                    }
                    niga_release_path(metaHandle)
                }
                found.append(SystemContainerItem(path: path, identifier: identifier, root: root))
            }

            found.sort { $0.identifier.localizedCaseInsensitiveCompare($1.identifier) == .orderedAscending }
            DispatchQueue.main.async {
                self.items = found
                self.status = "Found \(found.count) containers in \(root.title)"
            }
        }
    }
}
