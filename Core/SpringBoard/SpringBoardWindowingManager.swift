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
    static let path = "/var/mobile/Library/Preferences/com.apple.springboard.plist"

    private static let chamoisKey = "SBChamoisWindowingEnabled"
    private static let medusaKey = "SBMedusaMultitaskingEnabled"
    private static let automaticStageKey = "SBFlexibleWindowingAutomaticStageCreationEnabledExternal"
    private static let previousStageKey = "SBFlexibleWindowingPreviouslyEnabledAutomaticStageCreation"
    private static let wantsManyWindowsKey = "SBWantsManyForegroundWindows"
    private static let hasUsedMultiAppKey = "SBHasEverUsedMultiAppConfiguration"

    @Published var granted = false
    @Published var status = "SpringBoard prefs not connected"
    @Published var mode: SpringBoardWindowingMode = .fullScreen
    @Published var values: [String: Bool] = [:]
    @Published var backups: [URL] = []
    @Published var cfprefsSynchronized = false

    private var handle: Int64 = -1

    private var backupDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("SpringBoardBackups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func connect() {
        if handle >= 0 {
            granted = true
            refresh()
            return
        }

        // create=true deliberately skips the pre-grant lstat. Some builds allow
        // metadata reads here and some do not, while the bad_query token itself
        // can still grant the path.
        handle = SpringBoardWindowingManager.path.withCString { niga_escape_path($0, true) }
        granted = handle >= 0
        status = granted
            ? "SpringBoard preferences access granted"
            : "SpringBoard preferences grant failed: \(handle)"

        if granted {
            ensureOriginalBackup()
            refresh()
        }
    }

    func refresh() {
        guard granted else {
            status = "SpringBoard prefs not connected"
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
        guard granted else { throw notGrantedError() }
        _ = try snapshot(name: "before-\(newMode.rawValue)")
        let dict = try load()

        // Mirror SBContinuousExposeModuleController's real mode setter.
        switch newMode {
        case .fullScreen:
            dict[Self.chamoisKey] = false
            dict[Self.medusaKey] = false
            dict[Self.automaticStageKey] = false
        case .windowedApps:
            dict[Self.chamoisKey] = false
            dict[Self.medusaKey] = true
            dict[Self.automaticStageKey] = false
            // These are normal SpringBoard defaults on capable devices and help
            // the phone keep multiple foreground scenes instead of immediately
            // collapsing back to one full-screen scene.
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
        try data.write(to: URL(fileURLWithPath: Self.path), options: .atomic)

        // Also update cfprefsd's view of the same domain. If this call is rejected
        // on a particular beta, the verified direct plist write above still stands.
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
        guard granted else { throw notGrantedError() }
        let data = try Data(contentsOf: URL(fileURLWithPath: Self.path))
        _ = try dictionary(from: data)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = backupDirectory.appendingPathComponent("\(stamp)-\(name).plist")
        try data.write(to: url, options: .atomic)
        reloadBackups()
        return url
    }

    func restoreOriginal() throws {
        guard granted else { throw notGrantedError() }
        reloadBackups()
        guard let original = backups.first(where: { $0.lastPathComponent.contains("original") }) else {
            throw NSError(domain: "Niga.SpringBoard", code: 404, userInfo: [NSLocalizedDescriptionKey: "Original SpringBoard backup not found"])
        }
        _ = try snapshot(name: "pre-restore")
        let data = try Data(contentsOf: original)
        _ = try dictionary(from: data)
        try data.write(to: URL(fileURLWithPath: Self.path), options: .atomic)
        status = "Restored original SpringBoard preferences"
        refresh()
    }

    private func syncCFPreferences(_ newMode: SpringBoardWindowingMode) {
        let appID = "com.apple.springboard" as CFString
        let updates: [String: Bool]
        switch newMode {
        case .fullScreen:
            updates = [Self.chamoisKey: false, Self.medusaKey: false, Self.automaticStageKey: false]
        case .windowedApps:
            updates = [Self.chamoisKey: false, Self.medusaKey: true, Self.automaticStageKey: false, Self.wantsManyWindowsKey: true, Self.hasUsedMultiAppKey: true]
        case .stageManager:
            updates = [Self.chamoisKey: true, Self.medusaKey: true, Self.automaticStageKey: true, Self.previousStageKey: true, Self.wantsManyWindowsKey: true, Self.hasUsedMultiAppKey: true]
        }
        for (key, value) in updates {
            CFPreferencesSetAppValue(key as CFString, value ? kCFBooleanTrue : kCFBooleanFalse, appID)
        }
        cfprefsSynchronized = CFPreferencesAppSynchronize(appID)
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
        try dictionary(from: Data(contentsOf: URL(fileURLWithPath: Self.path)))
    }

    private func dictionary(from data: Data) throws -> NSMutableDictionary {
        guard let dict = try PropertyListSerialization.propertyList(
            from: data,
            options: [.mutableContainersAndLeaves],
            format: nil
        ) as? NSMutableDictionary else {
            throw NSError(domain: "Niga.SpringBoard", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid SpringBoard preferences plist"])
        }
        return dict
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return false
    }

    private func notGrantedError() -> NSError {
        NSError(domain: "Niga.SpringBoard", code: 1, userInfo: [NSLocalizedDescriptionKey: "Grant SpringBoard preferences access first"])
    }
}
