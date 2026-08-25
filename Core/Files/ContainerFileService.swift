import Foundation
import Combine

struct ContainerEntry: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    var name: String { url.lastPathComponent }
}

@MainActor
final class ContainerFileService: ObservableObject {
    @Published var entries: [ContainerEntry] = []
    @Published var status = ""
    private var handles: [String: Int64] = [:]

    private var backupDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("FileBackups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    deinit {
        for handle in handles.values { niga_release_path(handle) }
    }

    func grant(_ path: String) -> Bool {
        if handles[path] != nil { return true }
        let handle = path.withCString { niga_escape_path($0, false) }
        guard handle >= 0 else {
            status = "Sandbox grant failed: \(handle)"
            return false
        }
        handles[path] = handle
        return true
    }

    func list(_ url: URL) {
        let path = url.path
        guard grant(path) else { return }
        do {
            let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
            let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            entries = urls.map { item in
                let values = try? item.resourceValues(forKeys: Set(keys))
                return ContainerEntry(url: item, isDirectory: values?.isDirectory ?? false)
            }.sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory && !$1.isDirectory }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            status = "\(entries.count) items"
        } catch {
            status = error.localizedDescription
            entries = []
        }
    }

    func readText(_ url: URL) throws -> String {
        guard grant(url.path) else { throw NSError(domain: "Niga", code: 10, userInfo: [NSLocalizedDescriptionKey: status]) }
        let data = try Data(contentsOf: url)
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let pretty = try? JSONSerialization.data(withJSONObject: plist, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }
        if let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }
        return String(data: data, encoding: .utf8) ?? "<binary: \(data.count) bytes>"
    }

    func replaceFile(target: URL, with source: URL) throws {
        guard grant(target.path) else { throw NSError(domain: "Niga", code: 11, userInfo: [NSLocalizedDescriptionKey: status]) }
        let original = try Data(contentsOf: target)
        let safeName = target.path.replacingOccurrences(of: "/", with: "_")
        let backup = backupDirectory.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(safeName)")
        try original.write(to: backup, options: .atomic)

        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let replacement = try Data(contentsOf: source)
        try replacement.write(to: target)
        status = "Replaced \(target.lastPathComponent); backup saved"
    }

    func delete(_ url: URL) throws {
        guard grant(url.path) else { throw NSError(domain: "Niga", code: 12, userInfo: [NSLocalizedDescriptionKey: status]) }
        let data = try? Data(contentsOf: url)
        if let data {
            let safeName = url.path.replacingOccurrences(of: "/", with: "_")
            let backup = backupDirectory.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-deleted-\(safeName)")
            try? data.write(to: backup, options: .atomic)
        }
        try FileManager.default.removeItem(at: url)
        status = "Deleted \(url.lastPathComponent)"
    }
}
