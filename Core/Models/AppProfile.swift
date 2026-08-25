import Foundation
import Combine

enum WindowOrientation: String, Codable, CaseIterable, Identifiable, Hashable {
    case automatic, portrait, landscape
    var id: String { rawValue }
}

struct AppWindowProfile: Codable, Identifiable, Hashable {
    var id: String { bundleID }
    var bundleID: String
    var width: Double = 390
    var height: Double = 700
    var x: Double = 0
    var y: Double = 0
    var scale: Double = 1
    var orientation: WindowOrientation = .automatic
    var alwaysOnTop: Bool = false
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published var profiles: [String: AppWindowProfile] = [:]
    private let key = "niga.windowProfiles"
    init() { load() }
    func profile(for bundleID: String) -> AppWindowProfile { profiles[bundleID] ?? AppWindowProfile(bundleID: bundleID) }
    func save(_ profile: AppWindowProfile) { profiles[profile.bundleID] = profile; persist() }
    private func persist() { if let d = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(d, forKey: key) } }
    private func load() { if let d = UserDefaults.standard.data(forKey: key), let p = try? JSONDecoder().decode([String: AppWindowProfile].self, from: d) { profiles = p } }
}
