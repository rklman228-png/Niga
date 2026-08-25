import Foundation
import Combine

struct SceneStateHit: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let reason: String
    let snippet: String
}

@MainActor
final class SceneStateMiner: ObservableObject {
    @Published var hits: [SceneStateHit] = []
    @Published var status = "Idle"
    @Published var running = false

    private let needles = [
        "scene", "window", "stage", "workspace", "frontboard", "springboard",
        "medusa", "orientation", "geometry", "layout", "floating", "multitask"
    ]

    func scan(containerPath: String, maxFiles: Int = 6000, maxReadableBytes: Int = 1_500_000) {
        guard !running else { return }
        let searchNeedles = needles
        running = true
        status = "Mining scene/window state…"
        hits = []

        DispatchQueue.global(qos: .userInitiated).async {
            let handle = containerPath.withCString { niga_escape_path($0, false) }
            guard handle >= 0 else {
                DispatchQueue.main.async {
                    self.status = "Sandbox grant failed: \(handle)"
                    self.running = false
                }
                return
            }
            defer { niga_release_path(handle) }

            let root = URL(fileURLWithPath: containerPath, isDirectory: true)
            let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .isRegularFileKey]
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                DispatchQueue.main.async {
                    self.status = "Could not enumerate container"
                    self.running = false
                }
                return
            }

            var results: [SceneStateHit] = []
            var visited = 0
            while let value = enumerator.nextObject() as? URL, visited < maxFiles {
                visited += 1
                let rv = try? value.resourceValues(forKeys: Set(keys))
                if rv?.isDirectory == true { continue }

                let lowerPath = value.path.lowercased()
                let pathNeedles = searchNeedles.filter { lowerPath.contains($0) }
                if !pathNeedles.isEmpty {
                    results.append(SceneStateHit(
                        path: value.path,
                        reason: "filename/path: \(pathNeedles.joined(separator: ", "))",
                        snippet: ""
                    ))
                }

                guard rv?.isRegularFile != false,
                      let size = rv?.fileSize,
                      size > 0,
                      size <= maxReadableBytes else { continue }

                let ext = value.pathExtension.lowercased()
                let interestingExt = ["plist", "json", "txt", "strings", "db", "sqlite", "sqlite3", "conf", "xml"]
                guard interestingExt.contains(ext) || !pathNeedles.isEmpty else { continue }
                guard let data = try? Data(contentsOf: value) else { continue }

                var text: String?
                if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                   JSONSerialization.isValidJSONObject(plist),
                   let json = try? JSONSerialization.data(withJSONObject: plist, options: [.sortedKeys]),
                   let s = String(data: json, encoding: .utf8) {
                    text = s
                } else if let jsonObject = try? JSONSerialization.jsonObject(with: data),
                          JSONSerialization.isValidJSONObject(jsonObject),
                          let pretty = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys]),
                          let s = String(data: pretty, encoding: .utf8) {
                    text = s
                } else {
                    text = String(data: data, encoding: .utf8)
                }

                guard let original = text else { continue }
                let body = original.lowercased()
                let matches = searchNeedles.filter { body.contains($0) }
                guard !matches.isEmpty else { continue }

                let preview = String(original.prefix(700)).replacingOccurrences(of: "\n", with: " ")
                let hit = SceneStateHit(
                    path: value.path,
                    reason: "content: \(matches.joined(separator: ", "))",
                    snippet: preview
                )
                if let index = results.firstIndex(where: { $0.path == value.path }) {
                    results[index] = hit
                } else {
                    results.append(hit)
                }
            }

            results.sort { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
            DispatchQueue.main.async {
                self.hits = results
                self.status = "Scanned \(visited) files · \(results.count) candidate state files"
                self.running = false
            }
        }
    }
}
