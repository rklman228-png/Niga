import Foundation
import Combine
import Darwin
import MachO

@MainActor
final class GestaltManager: ObservableObject {
    static let shared = GestaltManager()
    static let path = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"

    private static let deviceClassKey = "mtrAoWJ3gsq+I90ZnQ0vQw"
    private static let canaryArmedKey = "Niga.DeviceClassCanary.Armed"
    private static let canaryOriginalKey = "Niga.DeviceClassCanary.Original"
    private static let canaryObservedKey = "Niga.DeviceClassCanary.ObservedEffective"
    private static let canaryDateKey = "Niga.DeviceClassCanary.Date"

    @Published var granted = false
    @Published var status = "Not connected"
    @Published var values: [WindowCapability: Bool] = [:]
    @Published var lastDiff: [String] = []
    @Published var backups: [URL] = []
    @Published var identityGuard = "Unknown"
    @Published var lastAppliedPreset: WindowExperimentPreset?

    @Published var rawDeviceClassNumber: Int?
    @Published var deviceClassCanaryStatus = "Not run"
    @Published var deviceClassCanaryLastEffective: Int?
    @Published var deviceClassCanaryArmed = false

    private var handle: Int64 = -1
    private var lastSnapshotURL: URL?
    private var cacheDataOffsets: [String: Int] = [:]

    private init() {
        let defaults = UserDefaults.standard
        deviceClassCanaryArmed = defaults.bool(forKey: Self.canaryArmedKey)
        if let observed = defaults.object(forKey: Self.canaryObservedKey) as? NSNumber {
            let value = observed.intValue
            deviceClassCanaryLastEffective = value
            if value == 2 {
                deviceClassCanaryStatus = "PASS: cold Niga process saw SBFEffectiveDeviceClass = 2; raw class was restored to iPhone immediately."
            } else {
                deviceClassCanaryStatus = "Canary completed: cold Niga process saw effective class \(value), not iPad-class 2. Raw class was restored."
            }
        } else if deviceClassCanaryArmed {
            deviceClassCanaryStatus = "RECOVERY PENDING: canary is armed. Niga will measure then restore the raw class on connect."
        }
    }

    private var backupDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("GestaltBackups", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func connect() {
        if handle >= 0 {
            granted = true
            if UserDefaults.standard.bool(forKey: Self.canaryArmedKey) {
                completeDeviceClassCanaryIfNeeded()
                return
            }
            refresh()
            return
        }

        handle = GestaltManager.path.withCString { niga_escape_path($0, false) }
        granted = handle >= 0
        status = granted ? "MobileGestalt access granted" : "Sandbox escape failed: \(handle)"
        if granted {
            // Canary recovery MUST happen before any normal probes load
            // SpringBoardFoundation/MobileGestalt state in this new process.
            if UserDefaults.standard.bool(forKey: Self.canaryArmedKey) {
                completeDeviceClassCanaryIfNeeded()
                return
            }
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
        rawDeviceClassNumber = readRawDeviceClass(from: dict)

        if rawDeviceClassNumber == 3 {
            identityGuard = "DANGER: raw DeviceClassNumber is currently iPad (3)"
        } else if next[.ipadIdentity] == true {
            identityGuard = "WARNING: iPad identity override is ON"
        } else {
            identityGuard = "Phone identity preserved"
        }
        deviceClassCanaryArmed = UserDefaults.standard.bool(forKey: Self.canaryArmedKey)
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
            // Phone-safe experiments never touch raw DeviceClassNumber.
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

    // MARK: - DeviceClass cold-start canary

    /// Writes only the raw DeviceClassNumber (1 -> 3), records the exact original
    /// value, then closes Niga. On the next launch connect() measures
    /// SBFEffectiveDeviceClass before restoring the original raw value and closes
    /// Niga again. A third launch is clean and displays the persisted result.
    func runDeviceClassCanary() throws {
        guard granted else { throw notGrantedError() }
        guard !UserDefaults.standard.bool(forKey: Self.canaryArmedKey) else {
            throw NSError(domain: "Niga.DeviceClassCanary", code: 20, userInfo: [NSLocalizedDescriptionKey: "A DeviceClass canary is already armed. Reopen Niga so automatic recovery can finish."])
        }

        let safety = try snapshot(name: "before-device-class-canary")
        let dict = try load()
        guard let cacheData = mutableCacheData(in: dict),
              let offset = cacheDataSafeOffset(Self.deviceClassKey, in: cacheData) else {
            throw NSError(domain: "Niga.DeviceClassCanary", code: 21, userInfo: [NSLocalizedDescriptionKey: "Could not locate DeviceClassNumber safely inside CacheData on this build. Nothing was changed."])
        }

        let original = cacheData.bytes.load(fromByteOffset: offset, as: Int.self)
        guard original == 1 else {
            throw NSError(domain: "Niga.DeviceClassCanary", code: 22, userInfo: [NSLocalizedDescriptionKey: "Refusing canary because raw DeviceClassNumber is \(original), expected stock iPhone value 1."])
        }

        let defaults = UserDefaults.standard
        defaults.set(original, forKey: Self.canaryOriginalKey)
        defaults.set(true, forKey: Self.canaryArmedKey)
        defaults.removeObject(forKey: Self.canaryObservedKey)
        defaults.removeObject(forKey: Self.canaryDateKey)
        defaults.synchronize()

        cacheData.mutableBytes.storeBytes(of: 3, toByteOffset: offset, as: Int.self)
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        do {
            try writeVerified(data, expectedLabel: "DeviceClass canary raw=3")
        } catch {
            if let backupData = try? Data(contentsOf: safety) {
                try? backupData.write(to: URL(fileURLWithPath: GestaltManager.path))
            }
            clearCanaryMarker()
            throw error
        }

        rawDeviceClassNumber = 3
        deviceClassCanaryArmed = true
        identityGuard = "CANARY: raw iPad class 3 is on disk until next Niga launch"
        deviceClassCanaryStatus = "Armed. Niga is closing now. Reopen it immediately; it will measure cold-process effective class, restore raw class 1, then close once more."
        status = "DeviceClass canary armed + verified"

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            Darwin.exit(0)
        }
    }

    func forceRestorePhoneDeviceClass() throws {
        guard granted else { throw notGrantedError() }
        let defaults = UserDefaults.standard
        let originalObject = defaults.object(forKey: Self.canaryOriginalKey) as? NSNumber
        let target = originalObject?.intValue ?? 1
        try writeRawDeviceClass(target, label: "forced DeviceClass recovery")
        clearCanaryMarker()
        rawDeviceClassNumber = target
        identityGuard = "Phone identity restored on disk"
        deviceClassCanaryStatus = "Forced recovery wrote raw DeviceClassNumber = \(target)."
        status = "DeviceClass recovered + verified"
        refresh()
    }

    private func completeDeviceClassCanaryIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.canaryArmedKey) else { return }

        deviceClassCanaryArmed = true
        deviceClassCanaryStatus = "Cold-start canary recovery in progress…"

        // Measure FIRST. This process has just launched and the raw class is still 3.
        let observed = Int(niga_sbs_effective_device_class())
        let target = (defaults.object(forKey: Self.canaryOriginalKey) as? NSNumber)?.intValue ?? 1

        do {
            try writeRawDeviceClass(target, label: "automatic post-canary DeviceClass restore")
            defaults.set(observed, forKey: Self.canaryObservedKey)
            defaults.set(Date(), forKey: Self.canaryDateKey)
            defaults.removeObject(forKey: Self.canaryArmedKey)
            defaults.removeObject(forKey: Self.canaryOriginalKey)
            defaults.synchronize()

            deviceClassCanaryArmed = false
            deviceClassCanaryLastEffective = observed
            rawDeviceClassNumber = target
            identityGuard = "Phone class restored on disk"
            deviceClassCanaryStatus = observed == 2
                ? "PASS: cold Niga saw effective iPad-class 2. Raw DeviceClassNumber has already been restored to \(target)."
                : "Canary measured effective class \(observed), then restored raw DeviceClassNumber to \(target)."
            status = "Canary measured + DeviceClass restored"

            // Exit so the next Niga process is clean too. Otherwise this process
            // may retain a cached iPad device class even though the plist is fixed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                Darwin.exit(0)
            }
        } catch {
            // Deliberately keep the armed marker so every future Niga launch retries
            // recovery before doing anything else.
            deviceClassCanaryStatus = "RECOVERY FAILED: \(error.localizedDescription). Do not reboot. Keep Niga open and use Force Restore Phone DeviceClass."
            status = "DeviceClass canary recovery FAILED"
            identityGuard = "DANGER: automatic DeviceClass recovery failed"
        }
    }

    private func clearCanaryMarker() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.canaryArmedKey)
        defaults.removeObject(forKey: Self.canaryOriginalKey)
        defaults.synchronize()
        deviceClassCanaryArmed = false
    }

    private func writeRawDeviceClass(_ value: Int, label: String) throws {
        guard granted else { throw notGrantedError() }
        let dict = try load()
        guard let cacheData = mutableCacheData(in: dict),
              let offset = cacheDataSafeOffset(Self.deviceClassKey, in: cacheData) else {
            throw NSError(domain: "Niga.DeviceClassCanary", code: 23, userInfo: [NSLocalizedDescriptionKey: "Could not locate DeviceClassNumber for recovery."])
        }
        cacheData.mutableBytes.storeBytes(of: value, toByteOffset: offset, as: Int.self)
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        try writeVerified(data, expectedLabel: label)

        let verifyDict = try load()
        let verifyValue = readRawDeviceClass(from: verifyDict)
        guard verifyValue == value else {
            throw NSError(domain: "Niga.DeviceClassCanary", code: 24, userInfo: [NSLocalizedDescriptionKey: "Raw DeviceClass verification failed: expected \(value), read \(String(describing: verifyValue))."])
        }
    }

    private func readRawDeviceClass(from dict: NSMutableDictionary) -> Int? {
        guard let cacheData = mutableCacheData(in: dict),
              let offset = cacheDataSafeOffset(Self.deviceClassKey, in: cacheData) else { return nil }
        return cacheData.bytes.load(fromByteOffset: offset, as: Int.self)
    }

    private func mutableCacheData(in dict: NSMutableDictionary) -> NSMutableData? {
        if let mutable = dict["CacheData"] as? NSMutableData {
            return mutable
        }
        if let data = dict["CacheData"] as? Data {
            let mutable = NSMutableData(data: data)
            dict["CacheData"] = mutable
            return mutable
        }
        if let data = dict["CacheData"] as? NSData {
            let mutable = NSMutableData(data: data as Data)
            dict["CacheData"] = mutable
            return mutable
        }
        return nil
    }

    // Mond's current iOS 27 MobileGestalt cache locator: find the hashed key in
    // libMobileGestalt's cstrings, find its metadata entry in __const, then read
    // the CacheData slot index from the metadata record. We bounds-check before use.
    private func cacheDataOffset(_ key: String) -> Int {
        if let cached = cacheDataOffsets[key] { return cached }

        let libMG = "/usr/lib/libMobileGestalt.dylib"
        dlopen(libMG, RTLD_GLOBAL)

        var header: UnsafePointer<mach_header_64>?
        for i in 0..<_dyld_image_count() {
            guard let imageName = _dyld_get_image_name(i) else { continue }
            if String(cString: imageName) == libMG {
                header = unsafeBitCast(_dyld_get_image_header(i), to: UnsafePointer<mach_header_64>.self)
                break
            }
        }
        guard let header else {
            cacheDataOffsets[key] = 0
            return 0
        }

        var textSize = 0
        guard let cstring = getsectiondata(header, "__TEXT", "__cstring", &textSize) else {
            cacheDataOffsets[key] = 0
            return 0
        }
        let cstr = cstring.withMemoryRebound(to: CChar.self, capacity: textSize) { $0 }

        var keyPtr = cstr
        var found = false
        while Int(keyPtr - cstr) < textSize {
            if String(cString: keyPtr) == key {
                found = true
                break
            }
            keyPtr += strlen(keyPtr) + 1
        }
        guard found else {
            cacheDataOffsets[key] = 0
            return 0
        }

        var constSize = 0
        var ptr = getsectiondata(header, "__AUTH_CONST", "__const", &constSize)?
            .withMemoryRebound(to: UInt.self, capacity: constSize / MemoryLayout<UInt>.size) { $0 }
        if ptr == nil {
            ptr = getsectiondata(header, "__DATA_CONST", "__const", &constSize)?
                .withMemoryRebound(to: UInt.self, capacity: constSize / MemoryLayout<UInt>.size) { $0 }
        }

        guard let ptr else {
            cacheDataOffsets[key] = 0
            return 0
        }

        for i in 0..<(constSize / MemoryLayout<UInt>.size) {
            if ptr[i] == UInt(bitPattern: keyPtr) {
                let offset = Int((ptr.advanced(by: i).withMemoryRebound(to: UInt16.self, capacity: 1) { $0[0x9a / 2] }) << 3)
                cacheDataOffsets[key] = offset
                return offset
            }
        }

        cacheDataOffsets[key] = 0
        return 0
    }

    private func cacheDataSafeOffset(_ key: String, in data: NSMutableData) -> Int? {
        let offset = cacheDataOffset(key)
        guard offset > 0, offset <= data.length - MemoryLayout<Int>.size else { return nil }
        return offset
    }

    // MARK: - Backups / ordinary MobileGestalt mutations

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
