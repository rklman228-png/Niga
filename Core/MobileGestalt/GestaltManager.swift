import Foundation

@MainActor
final class GestaltManager: ObservableObject {
    static let shared = GestaltManager()
    static let path = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"

    @Published var granted = false
    @Published var status = "Not connected"
    @Published var values: [WindowCapability: Bool] = [:]
    @Published var lastDiff: [String] = []
    @Published var backups: [URL] = []
    private var handle: Int64 = -1

    private var backupDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("GestaltBackups", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func connect() {
        if handle >= 0 { granted = true; refresh(); return }
        handle = GestaltManager.path.withCString { niga_escape_path($0, false) }
        granted = handle >= 0
        status = granted ? "MobileGestalt access granted" : "Sandbox escape failed: \(handle)"
        if granted { ensureOriginalBackup(); refresh() }
    }

    func refresh() {
        guard let dict = try? load() else { status = "Failed to read MobileGestalt"; return }
        let extra = dict["CacheExtra"] as? NSDictionary
        var next: [WindowCapability: Bool] = [:]
        for cap in WindowCapability.allCases { next[cap] = (extra?[cap.rawValue] as? Int) == 1 }
        values = next
        reloadBackups()
    }

    func set(_ cap: WindowCapability, enabled: Bool) throws {
        try mutate(label: "\(cap.title)=\(enabled)") { extra in
            if enabled { extra[cap.rawValue] = 1 } else { extra.removeObject(forKey: cap.rawValue) }
        }
        refresh()
    }

    func apply(_ preset: WindowPreset) throws {
        try mutate(label: preset.title) { extra in
            switch preset {
            case .stageOnly:
                for cap in WindowCapability.allCases { extra.removeObject(forKey: cap.rawValue) }
                extra[WindowCapability.stageManager.rawValue] = 1
            case .phoneWindowing:
                for cap in WindowCapability.allCases { extra[cap.rawValue] = 1 }
            case .clearWindowing:
                for cap in WindowCapability.allCases { extra.removeObject(forKey: cap.rawValue) }
            }
        }
        refresh()
    }

    func snapshot(name: String = "manual") throws -> URL {
        let data = try Data(contentsOf: URL(fileURLWithPath: GestaltManager.path))
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = backupDirectory.appendingPathComponent("\(stamp)-\(name).plist")
        try data.write(to: url, options: .atomic)
        reloadBackups(); return url
    }

    func diffAgainstLatestBackup() throws {
        guard let baselineURL = backups.dropFirst().first ?? backups.first else { lastDiff = ["No backup available"]; return }
        let before = try dictionary(from: Data(contentsOf: baselineURL))
        let after = try load()
        let a = (before["CacheExtra"] as? NSDictionary) ?? [:]
        let b = (after["CacheExtra"] as? NSDictionary) ?? [:]
        let keys = Set(a.allKeys.compactMap { $0 as? String }).union(b.allKeys.compactMap { $0 as? String })
        lastDiff = keys.sorted().compactMap { key in
            let lhs = a[key]; let rhs = b[key]
            if String(describing: lhs) == String(describing: rhs) { return nil }
            return "\(key): \(String(describing: lhs)) → \(String(describing: rhs))"
        }
        if lastDiff.isEmpty { lastDiff = ["No CacheExtra changes"] }
    }

    func restore(_ url: URL) throws {
        _ = try snapshot(name: "pre-restore")
        let data = try Data(contentsOf: url)
        _ = try dictionary(from: data)
        try data.write(to: URL(fileURLWithPath: GestaltManager.path))
        status = "Restored \(url.lastPathComponent)"
        refresh()
    }

    func restoreOriginal() throws {
        reloadBackups()
        guard let original = backups.first(where: { $0.lastPathComponent.contains("original") }) else { throw NSError(domain: "Niga", code: 404, userInfo: [NSLocalizedDescriptionKey: "Original backup not found"]) }
        try restore(original)
    }

    private func mutate(label: String, block: (NSMutableDictionary) -> Void) throws {
        guard granted else { throw NSError(domain: "Niga", code: 1, userInfo: [NSLocalizedDescriptionKey: "Grant MobileGestalt access first"]) }
        _ = try snapshot(name: "before-change")
        let dict = try load()
        let extra: NSMutableDictionary
        if let e = dict["CacheExtra"] as? NSMutableDictionary { extra = e }
        else if let e = dict["CacheExtra"] as? NSDictionary { extra = NSMutableDictionary(dictionary: e); dict["CacheExtra"] = extra }
        else { extra = NSMutableDictionary(); dict["CacheExtra"] = extra }
        block(extra)
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        try data.write(to: URL(fileURLWithPath: GestaltManager.path))
        status = "Applied: \(label)"
    }

    private func ensureOriginalBackup() {
        reloadBackups()
        guard !backups.contains(where: { $0.lastPathComponent.contains("original") }) else { return }
        _ = try? snapshot(name: "original")
    }

    private func reloadBackups() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        backups = urls.filter { $0.pathExtension == "plist" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func load() throws -> NSMutableDictionary {
        try dictionary(from: Data(contentsOf: URL(fileURLWithPath: GestaltManager.path)))
    }

    private func dictionary(from data: Data) throws -> NSMutableDictionary {
        guard let dict = try PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary else {
            throw NSError(domain: "Niga", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid MobileGestalt plist"])
        }
        return dict
    }
}
