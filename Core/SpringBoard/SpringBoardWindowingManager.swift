import Foundation
import Combine
import CoreFoundation

enum SpringBoardWindowingMode: Int, CaseIterable, Identifiable {
    case fullScreen = 0
    case windowedApps = 1
    case stageManager = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .fullScreen: return "Full Screen Apps"
        case .windowedApps: return "Windowed Apps"
        case .stageManager: return "Stage Manager"
        }
    }

    var detail: String {
        switch self {
        case .fullScreen:
            return "Stock iPhone-style full-screen app mode."
        case .windowedApps:
            return "Apple's flexible Windowed Apps mode: Medusa on, Chamois/Stage Manager off."
        case .stageManager:
            return "Apple's Stage Manager mode: Chamois on with automatic stage creation."
        }
    }
}

@MainActor
final class SpringBoardWindowingManager: ObservableObject {
    static let shared = SpringBoardWindowingManager()

    private static let legacyPath = "/var/mobile/Library/Preferences/com.apple.springboard.plist"
    private static let preferenceName = "com.apple.springboard.plist"

    private static let chamoisKey = "SBChamoisWindowingEnabled"
    private static let medusaKey = "SBMedusaMultitaskingEnabled"
    private static let automaticStageKey = "SBFlexibleWindowingAutomaticStageCreationEnabledExternal"
    private static let previousStageKey = "SBFlexibleWindowingPreviouslyEnabledAutomaticStageCreation"
    private static let wantsManyWindowsKey = "SBWantsManyForegroundWindows"
    private static let hasUsedMultiAppKey = "SBHasEverUsedMultiAppConfiguration"

    @Published var granted = false
    @Published var isDiscovering = false
    @Published var status = "SpringBoard prefs not connected"
    @Published var mode: SpringBoardWindowingMode = .fullScreen
    @Published var values: [String: Bool] = [:]
    @Published var backups: [URL] = []
    @Published var cfprefsSynchronized = false
    @Published var resolvedPath = ""
    @Published var accessSource = ""
    @Published var discoveryDetails = "Not attempted"

    private var leases: [Int64] = []
    private var discoveryGeneration = 0

    private struct DiscoveryResult {
        let path: String?
        let source: String
        let handles: [Int64]
        let details: String
    }

    private var backupDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("SpringBoardBackups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func connect() {
        if granted, !resolvedPath.isEmpty {
            refresh()
            return
        }
        guard !isDiscovering else { return }

        // v0.6 assumed this historical global prefs path was reachable. Your
        // iOS 27 DB3 screenshot proved it is not: bad_query returned -3 because
        // /var/mobile/Library/Preferences is outside the exposed MCM roots.
        let legacyHandle = Self.legacyPath.withCString { niga_escape_path($0, true) }
        if legacyHandle >= 0, Self.validPreferencesFile(Self.legacyPath) {
            activate(path: Self.legacyPath,
                     source: "legacy /var/mobile preferences",
                     handles: [legacyHandle],
                     details: "Legacy SpringBoard preferences path was directly reachable.")
            return
        }
        if legacyHandle >= 0 { niga_release_path(legacyHandle) }

        isDiscovering = true
        granted = false
        discoveryGeneration += 1
        let generation = discoveryGeneration
        status = "Legacy path blocked (\(legacyHandle)); locating SpringBoard system container…"
        discoveryDetails = "Direct legacy bad_query result: \(legacyHandle). Trying MCM class 12/10/13, then Data/System inode discovery."

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.discoverPreferences(legacyCode: legacyHandle)
            DispatchQueue.main.async {
                guard generation == self.discoveryGeneration else {
                    for handle in result.handles { niga_release_path(handle) }
                    return
                }
                self.finishDiscovery(result)
            }
        }
    }

    func rediscover() {
        discoveryGeneration += 1
        releaseLeases()
        granted = false
        isDiscovering = false
        resolvedPath = ""
        accessSource = ""
        values = [:]
        mode = .fullScreen
        cfprefsSynchronized = false
        status = "Resetting SpringBoard resolver…"
        discoveryDetails = "Resolver reset by user."
        connect()
    }

    func refresh() {
        guard granted, !resolvedPath.isEmpty else {
            if !isDiscovering { status = "SpringBoard prefs not connected" }
            return
        }
        do {
            let dict = try load()
            let keys = [
                Self.chamoisKey,
                Self.medusaKey,
                Self.automaticStageKey,
                Self.previousStageKey,
                Self.wantsManyWindowsKey,
                Self.hasUsedMultiAppKey
            ]
            values = Dictionary(uniqueKeysWithValues: keys.map { ($0, boolValue(dict[$0])) })

            if values[Self.chamoisKey] == true {
                mode = .stageManager
            } else if values[Self.medusaKey] == true {
                mode = .windowedApps
            } else {
                mode = .fullScreen
            }
            status = "SpringBoard mode: \(mode.title)"
            reloadBackups()
        } catch {
            status = "SpringBoard plist read failed: \(error.localizedDescription)"
        }
    }

    func apply(_ newMode: SpringBoardWindowingMode) throws {
        guard granted, !resolvedPath.isEmpty else { throw notGrantedError() }
        _ = try snapshot(name: "before-\(newMode.rawValue)")
        let dict = try load()

        // Mirrors the actual SBContinuousExposeModuleController mode mapping.
        switch newMode {
        case .fullScreen:
            dict[Self.chamoisKey] = false
            dict[Self.medusaKey] = false
            dict[Self.automaticStageKey] = false
        case .windowedApps:
            dict[Self.chamoisKey] = false
            dict[Self.medusaKey] = true
            dict[Self.automaticStageKey] = false
            dict[Self.wantsManyWindowsKey] = true
            dict[Self.hasUsedMultiAppKey] = true
        case .stageManager:
            dict[Self.chamoisKey] = true
            dict[Self.medusaKey] = true
            dict[Self.automaticStageKey] = true
            dict[Self.previousStageKey] = true
            dict[Self.wantsManyWindowsKey] = true
            dict[Self.hasUsedMultiAppKey] = true
        }

        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        try writeVerified(data, label: newMode.title)

        // This is best-effort. The important success criterion is the verified
        // write to SpringBoard's *real resolved container* above.
        syncCFPreferences(newMode)

        let reread = try load()
        let expectedChamois = newMode == .stageManager
        let expectedMedusa = newMode != .fullScreen
        guard boolValue(reread[Self.chamoisKey]) == expectedChamois,
              boolValue(reread[Self.medusaKey]) == expectedMedusa else {
            throw NSError(domain: "Niga.SpringBoard", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "SpringBoard mode write did not survive re-read"
            ])
        }

        mode = newMode
        status = "Applied + verified SpringBoard mode: \(newMode.title)"
        refresh()
    }

    func snapshot(name: String = "manual") throws -> URL {
        guard granted, !resolvedPath.isEmpty else { throw notGrantedError() }
        let data = try Data(contentsOf: URL(fileURLWithPath: resolvedPath))
        _ = try dictionary(from: data)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = backupDirectory.appendingPathComponent("\(stamp)-\(backupIdentity)-\(name).plist")
        try data.write(to: url, options: .atomic)
        reloadBackups()
        return url
    }

    func restoreOriginal() throws {
        guard granted, !resolvedPath.isEmpty else { throw notGrantedError() }
        reloadBackups()
        let marker = "-\(backupIdentity)-original.plist"
        guard let original = backups.first(where: { $0.lastPathComponent.hasSuffix(marker) }) else {
            throw NSError(domain: "Niga.SpringBoard", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Original SpringBoard backup for this container was not found"
            ])
        }
        _ = try snapshot(name: "pre-restore")
        let data = try Data(contentsOf: original)
        _ = try dictionary(from: data)
        try writeVerified(data, label: "original restore")
        status = "Restored original SpringBoard preferences"
        refresh()
    }

    private func activate(path: String, source: String, handles: [Int64], details: String) {
        releaseLeases()
        leases = handles.filter { $0 >= 0 }
        resolvedPath = path
        accessSource = source
        discoveryDetails = details
        granted = true
        isDiscovering = false
        status = "SpringBoard preferences access granted"
        ensureOriginalBackup()
        refresh()
    }

    private func finishDiscovery(_ result: DiscoveryResult) {
        isDiscovering = false
        if let path = result.path {
            activate(path: path, source: result.source, handles: result.handles, details: result.details)
        } else {
            for handle in result.handles { niga_release_path(handle) }
            granted = false
            resolvedPath = ""
            accessSource = ""
            status = "Could not locate an accessible SpringBoard preferences container"
            discoveryDetails = result.details
        }
    }

    private func releaseLeases() {
        for handle in leases where handle >= 0 { niga_release_path(handle) }
        leases.removeAll()
    }

    private static func discoverPreferences(legacyCode: Int64) -> DiscoveryResult {
        var notes: [String] = ["legacy=\(legacyCode)"]

        // Fast path: ask ContainerManager for the real UUID-backed container
        // root. Even when it does not hand our signed app a usable token, the
        // metadata lookup can reveal the path, after which bad_query can grant
        // the iOS 27 Data/System location.
        let directQueries: [(UInt64, String, Bool, String)] = [
            (12, "com.apple.springboard", false, "MCM class 12 com.apple.springboard"),
            (10, "com.apple.springboard", false, "MCM class 10 com.apple.springboard"),
            (13, "systemgroup.com.apple.springboard", true, "MCM class 13 systemgroup.com.apple.springboard"),
            (13, "systemgroup.com.apple.springboard.shared", true, "MCM class 13 springboard.shared")
        ]

        for (containerClass, identifier, group, label) in directQueries {
            guard let root = mcmPath(containerClass: containerClass, identifier: identifier, group: group) else {
                notes.append("\(label): no metadata path")
                continue
            }
            notes.append("\(label): \(root)")
            if let hit = inspectContainer(root: root, expectedIdentifier: identifier, source: label) {
                let detail = (notes + ["resolved=\(hit.path)"]).joined(separator: "\n")
                return DiscoveryResult(path: hit.path, source: hit.source, handles: hit.handles, details: detail)
            }
        }

        // bad_query explicitly exposes /var/containers/Data/System and
        // /var/containers/Shared/SystemGroup on iOS 27. If the MCM metadata
        // lookup is filtered, recover the UUID roots with fsgetpath just like
        // the upstream PoC/3105-style container scanners.
        let roots = [
            "/var/containers/Data/System",
            "/var/mobile/Containers/Data/System",
            "/var/containers/Shared/SystemGroup"
        ]

        for root in roots {
            guard let ptr = root.withCString({ niga_list_children($0, 1_500_000) }) else {
                notes.append("\(root): inode listing unavailable")
                continue
            }
            let listing = String(cString: ptr)
            niga_free_string(ptr)
            let children = listing.split(separator: "\n").map(String.init)
            notes.append("\(root): \(children.count) child paths")

            // First pass: metadata says SpringBoard.
            var deferred: [(String, String)] = []
            for child in children {
                let handle = child.withCString { niga_escape_path($0, true) }
                guard handle >= 0 else { continue }

                let identifier = metadataIdentifier(at: child) ?? ""
                if identifier.localizedCaseInsensitiveContains("springboard") {
                    if let file = findPreferencesFile(in: child) {
                        notes.append("metadata hit \(identifier) -> \(file)")
                        return DiscoveryResult(
                            path: file,
                            source: "iOS 27 \(root) metadata scan (\(identifier))",
                            handles: [handle],
                            details: (notes + ["resolved=\(file)"]).joined(separator: "\n")
                        )
                    }
                    deferred.append((child, identifier))
                }

                // Exact filename is strong enough even if metadata is hidden.
                let exact = child + "/Library/Preferences/" + preferenceName
                if validPreferencesFile(exact) {
                    notes.append("filename hit -> \(exact)")
                    return DiscoveryResult(
                        path: exact,
                        source: "iOS 27 \(root) filename scan",
                        handles: [handle],
                        details: (notes + ["resolved=\(exact)"]).joined(separator: "\n")
                    )
                }
                niga_release_path(handle)
            }

            // A SpringBoard-labelled container may use a slightly different
            // preferences filename on a beta. Search only those containers,
            // not the whole filesystem.
            for (child, identifier) in deferred {
                let handle = child.withCString { niga_escape_path($0, true) }
                guard handle >= 0 else { continue }
                if let file = findPreferencesFileRecursively(in: child) {
                    notes.append("recursive hit \(identifier) -> \(file)")
                    return DiscoveryResult(
                        path: file,
                        source: "iOS 27 \(root) SpringBoard recursive scan",
                        handles: [handle],
                        details: (notes + ["resolved=\(file)"]).joined(separator: "\n")
                    )
                }
                niga_release_path(handle)
            }
        }

        notes.append("No readable com.apple.springboard.plist was found inside bad_query's exposed iOS 27 MCM roots.")
        return DiscoveryResult(path: nil, source: "", handles: [], details: notes.joined(separator: "\n"))
    }

    private static func inspectContainer(root rawRoot: String,
                                         expectedIdentifier: String,
                                         source: String) -> DiscoveryResult? {
        let root = canonicalVarPath(rawRoot)
        let handle = root.withCString { niga_escape_path($0, true) }
        guard handle >= 0 else { return nil }

        if let file = findPreferencesFile(in: root) ?? findPreferencesFileRecursively(in: root),
           validPreferencesFile(file) {
            return DiscoveryResult(path: file,
                                   source: source,
                                   handles: [handle],
                                   details: "Resolved \(expectedIdentifier) at \(file)")
        }

        niga_release_path(handle)
        return nil
    }

    private static func mcmPath(containerClass: UInt64, identifier: String, group: Bool) -> String? {
        let ptr = identifier.withCString { niga_mcm_container_path(containerClass, $0, group) }
        guard let ptr else { return nil }
        defer { niga_free_string(ptr) }
        let value = String(cString: ptr)
        return value.isEmpty ? nil : canonicalVarPath(value)
    }

    private static func canonicalVarPath(_ value: String) -> String {
        if value == "/private/var" { return "/var" }
        if value.hasPrefix("/private/var/") { return String(value.dropFirst(8)) }
        return value
    }

    private static func metadataIdentifier(at container: String) -> String? {
        let path = container + "/.com.apple.mobile_container_manager.metadata.plist"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return dict["MCMMetadataIdentifier"] as? String
    }

    private static func findPreferencesFile(in root: String) -> String? {
        let candidates = [
            root + "/Library/Preferences/com.apple.springboard.plist",
            root + "/Library/Preferences/com.apple.SpringBoard.plist",
            root + "/Preferences/com.apple.springboard.plist"
        ]
        return candidates.first(where: { validPreferencesFile($0) })
    }

    private static func findPreferencesFileRecursively(in root: String) -> String? {
        let fm = FileManager.default
        let preferredRoot = root + "/Library/Preferences"
        let searchRoot = fm.fileExists(atPath: preferredRoot) ? preferredRoot : root
        guard let enumerator = fm.enumerator(atPath: searchRoot) else { return nil }

        var inspected = 0
        while let item = enumerator.nextObject() as? String, inspected < 5000 {
            inspected += 1
            let lower = item.lowercased()
            guard lower.hasSuffix(".plist"), lower.contains("springboard") else { continue }
            let candidate = searchRoot + "/" + item
            if validPreferencesFile(candidate) { return candidate }
        }
        return nil
    }

    private static func validPreferencesFile(_ path: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return false }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) is NSDictionary
            || (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) is [String: Any]
    }

    private func writeVerified(_ data: Data, label: String) throws {
        guard !resolvedPath.isEmpty else { throw notGrantedError() }
        let url = URL(fileURLWithPath: resolvedPath)

        // Do not use .atomic here. Atomic replacement creates a sibling temp
        // file and can require broader directory authority than the consumed
        // bad_query extension. Write the already-backed-up file in place.
        try data.write(to: url, options: [])
        if let handle = try? FileHandle(forWritingTo: url) {
            try? handle.synchronize()
            try? handle.close()
        }

        let reread = try Data(contentsOf: url)
        _ = try dictionary(from: reread)
        guard reread == data else {
            throw NSError(domain: "Niga.SpringBoard", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Write verification failed for \(label)"
            ])
        }
    }

    private func syncCFPreferences(_ newMode: SpringBoardWindowingMode) {
        let appID = "com.apple.springboard" as CFString
        let updates: [String: Bool]
        switch newMode {
        case .fullScreen:
            updates = [Self.chamoisKey: false, Self.medusaKey: false, Self.automaticStageKey: false]
        case .windowedApps:
            updates = [Self.chamoisKey: false, Self.medusaKey: true, Self.automaticStageKey: false,
                       Self.wantsManyWindowsKey: true, Self.hasUsedMultiAppKey: true]
        case .stageManager:
            updates = [Self.chamoisKey: true, Self.medusaKey: true, Self.automaticStageKey: true,
                       Self.previousStageKey: true, Self.wantsManyWindowsKey: true,
                       Self.hasUsedMultiAppKey: true]
        }
        for (key, value) in updates {
            CFPreferencesSetAppValue(key as CFString,
                                     value ? kCFBooleanTrue : kCFBooleanFalse,
                                     appID)
        }
        cfprefsSynchronized = CFPreferencesAppSynchronize(appID)
    }

    private var backupIdentity: String {
        let components = resolvedPath.split(separator: "/").map(String.init)
        if let uuid = components.first(where: { UUID(uuidString: $0) != nil }) {
            return uuid
        }
        return resolvedPath == Self.legacyPath ? "legacy" : "springboard"
    }

    private func ensureOriginalBackup() {
        reloadBackups()
        let marker = "-\(backupIdentity)-original.plist"
        guard !backups.contains(where: { $0.lastPathComponent.hasSuffix(marker) }) else { return }
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
        guard !resolvedPath.isEmpty else { throw notGrantedError() }
        return try dictionary(from: Data(contentsOf: URL(fileURLWithPath: resolvedPath)))
    }

    private func dictionary(from data: Data) throws -> NSMutableDictionary {
        guard let dict = try PropertyListSerialization.propertyList(
            from: data,
            options: [.mutableContainersAndLeaves],
            format: nil
        ) as? NSMutableDictionary else {
            throw NSError(domain: "Niga.SpringBoard", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid SpringBoard preferences plist"
            ])
        }
        return dict
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return false
    }

    private func notGrantedError() -> NSError {
        let suffix = isDiscovering ? " (resolver is still scanning)" : ""
        return NSError(domain: "Niga.SpringBoard", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "SpringBoard preferences access is not ready\(suffix)"
        ])
    }
}
