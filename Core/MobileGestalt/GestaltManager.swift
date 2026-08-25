import Foundation
import Combine

@MainActor
final class GestaltManager: ObservableObject {
    static let shared = GestaltManager()
    static let path = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"

    @Published var granted = false
    @Published var status = "Not connected"
    @Published var values: [WindowCapability: Bool] = [:]
    @Published var lastDiff: [String] = []
    @Published var backups: [URL] = []
    @Published var identityGuard = "Unknown"
    @Published var lastAppliedPreset: WindowExperimentPreset?

    private var handle: Int64 = -1
    private var lastSnapshotURL: URL?

    private var backupDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("GestaltBackups", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func connect() {
        if handle >= 0 {
            granted = true
            refresh()
            return
        }
        handle = GestaltManager.path.withCString { niga_escape_path($0, false) }
        granted = handle >= 0
        status = granted ? "MobileGestalt access granted" : "Sandbox escape failed: \(handle)"
        if granted {
            ensureOriginalBackup()
            refresh()
        }
    }

    func refresh() {
        guard let dict = try? load() else {
            status = "Failed to read MobileGestalt"
            return
        }
        let extra = dict["CacheExtra"] as? NSDictionary
        var next: [WindowCapability: Bool] = [:]
        for cap in WindowCapability.allCases {
            next[cap] = (extra?[cap.rawValue] as? Int) == 1
        }
        values = next
        identityGuard = (next[.ipadIdentity] == true)
            ? "WARNING: iPad identity override is ON"
            : "Phone identity preserved"
        reloadBackups()
    }

    func set(_ cap: WindowCapability, enabled: Bool) throws {
        try mutate(label: "\(cap.title)=\(enabled)") { extra in
            if enabled { extra[cap.rawValue] = 1 }
            else { extra.removeObject(forKey: cap.rawValue) }
        }
        refresh()
    }

    func apply(_ preset: WindowPreset) throws {
        switch preset {
        case .stageOnly:
            try applyExperiment(.stageOnly)
        case .phoneWindowing:
            try applyExperiment(.stageAllMedusa)
        case .clearWindowing:
            try applyExperiment(.clear)
        }
    }

    func applyExperiment(_ preset: WindowExperimentPreset) throws {
        try mutate(label: preset.title) { extra in
            // Every experiment in this matrix is deliberately phone-safe. The
            // iPad identity override is always removed first and DeviceClassNumber
            // is never touched by this app.
            extra.removeObject(forKey: WindowCapability.ipadIdentity.rawValue)
            for cap in WindowCapability.phoneSafeWindowing {
                extra.removeObject(forKey: cap.rawValue)
            }
            for cap in preset.enabled {
                extra[cap.rawValue] = 1
            }
        }
        lastAppliedPreset = preset
        refresh()
    }

    func snapshot(name: String = "manual") throws -> URL {
        let data = try Data(contentsOf: URL(fileURLWithPath: GestaltManager.path))
        _ = try dictionary(from: data)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = backupDirectory.appendingPathComponent("\(stamp)-\(name).plist")
        try data.write(to: url, options: .atomic)
        lastSnapshotURL = url
        reloadBackups()
        return url
    }

    func diffAgainstLatestBackup() throws {
        reloadBackups()
        let baselineURL = lastSnapshotURL ?? backups.first(where: { !$0.lastPathComponent.contains("original") }) ?? backups.first
        guard let baselineURL else {
            lastDiff = ["No backup available"]
            return
        }
        let before = try dictionary(from: Data(contentsOf: baselineURL))
        let after = try load()
        let a = (before["CacheExtra"] as? NSDictionary) ?? NSDictionary()
        let b = (after["CacheExtra"] as? NSDictionary) ?? NSDictionary()
        let keys = Set(a.allKeys.compactMap { $0 as? String })
            .union(b.allKeys.compactMap { $0 as? String })
        lastDiff = keys.sorted().compactMap { key in
            let lhs = a[key]
            let rhs = b[key]
            if valuesEqual(lhs, rhs) { return nil }
            return "\(key): \(String(describing: lhs)) → \(String(describing: rhs))"
        }
        if lastDiff.isEmpty { lastDiff = ["No CacheExtra changes"] }
    }

    func restore(_ url: URL) throws {
        guard granted else { throw notGrantedError() }
        _ = try snapshot(name: "pre-restore")
        let data = try Data(contentsOf: url)
        _ = try dictionary(from: data)
        try writeVerified(data, expectedLabel: "restore \(url.lastPathComponent)")
        status = "Restored \(url.lastPathComponent)"
        refresh()
    }

    func restoreOriginal() throws {
        reloadBackups()
        guard let original = backups.first(where: { $0.lastPathComponent.contains("original") }) else {
            throw NSError(domain: "Niga", code: 404, userInfo: [NSLocalizedDescriptionKey: "Original backup not found"])
        }
        try restore(original)
    }

    private func mutate(label: String, block: (NSMutableDictionary) -> Void) throws {
        guard granted else { throw notGrantedError() }
        let safety = try snapshot(name: "before-change")
        let dict = try load()
        let extra: NSMutableDictionary
        if let e = dict["CacheExtra"] as? NSMutableDictionary {
            extra = e
        } else if let e = dict["CacheExtra"] as? NSDictionary {
            extra = NSMutableDictionary(dictionary: e)
            dict["CacheExtra"] = extra
        } else {
            extra = NSMutableDictionary()
            dict["CacheExtra"] = extra
        }

        block(extra)
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        do {
            try writeVerified(data, expectedLabel: label)
            status = "Applied + verified: \(label)"
        } catch {
            // Best-effort rollback to the exact pre-change bytes if verification fails.
            if let backupData = try? Data(contentsOf: safety) {
                try? backupData.write(to: URL(fileURLWithPath: GestaltManager.path))
            }
            throw error
        }
    }

    private func writeVerified(_ data: Data, expectedLabel: String) throws {
        let target = URL(fileURLWithPath: GestaltManager.path)
        try data.write(to: target)
        let reread = try Data(contentsOf: target)
        _ = try dictionary(from: reread)
        guard reread == data else {
            throw NSError(domain: "Niga", code: 3, userInfo: [NSLocalizedDescriptionKey: "Write verification failed for \(expectedLabel)"])
        }
    }

    private func ensureOriginalBackup() {
        reloadBackups()
        guard !backups.contains(where: { $0.lastPathComponent.contains("original") }) else { return }
        _ = try? snapshot(name: "original")
    }

    private func reloadBackups() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        backups = urls.filter { $0.pathExtension == "plist" }.sorted {
            let l = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }
    }

    private func load() throws -> NSMutableDictionary {
        try dictionary(from: Data(contentsOf: URL(fileURLWithPath: GestaltManager.path)))
    }

    private func dictionary(from data: Data) throws -> NSMutableDictionary {
        guard let dict = try PropertyListSerialization.propertyList(
            from: data,
            options: [.mutableContainersAndLeaves],
            format: nil
        ) as? NSMutableDictionary else {
            throw NSError(domain: "Niga", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid MobileGestalt plist"])
        }
        return dict
    }

    private func valuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (l as NSObject, r as NSObject): return l == r
        default: return String(describing: lhs) == String(describing: rhs)
        }
    }

    private func notGrantedError() -> NSError {
        NSError(domain: "Niga", code: 1, userInfo: [NSLocalizedDescriptionKey: "Grant MobileGestalt access first"])
    }
}
