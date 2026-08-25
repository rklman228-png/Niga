import Foundation

struct InstalledContainer: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let bundleID: String
    let displayName: String
}

final class AppContainerScanner: ObservableObject {
    @Published var apps: [InstalledContainer] = []
    @Published var status = "Not scanned"

    func scan(maxInode: Int64 = 500_000) {
        status = "Scanning…"
        DispatchQueue.global(qos: .userInitiated).async {
            let root = "/var/mobile/Containers/Data/Application"
            guard let ptr = niga_list_children(root, maxInode) else {
                DispatchQueue.main.async { self.status = "Container enumeration failed" }; return
            }
            let text = String(cString: ptr); niga_free_string(ptr)
            let paths = text.split(separator: "\n").map(String.init)
            var found: [InstalledContainer] = []
            for path in paths {
                let meta = path + "/.com.apple.mobile_container_manager.metadata.plist"
                let h = meta.withCString { niga_escape_path($0, false) }
                guard h >= 0 else { continue }
                defer { niga_release_path(h) }
                guard let d = NSDictionary(contentsOfFile: meta) else { continue }
                let bid = (d["MCMMetadataIdentifier"] as? String) ?? "unknown"
                let name = bid.split(separator: ".").last.map(String.init) ?? bid
                found.append(.init(path: path, bundleID: bid, displayName: name))
            }
            found.sort { $0.bundleID.localizedCaseInsensitiveCompare($1.bundleID) == .orderedAscending }
            DispatchQueue.main.async { self.apps = found; self.status = "Found \(found.count) containers" }
        }
    }
}
