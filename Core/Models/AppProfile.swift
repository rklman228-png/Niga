import Foundation
import Combine

enum WindowOrientation: String, Codable, CaseIterable, Identifiable, Hashable {
    case automatic, portrait, landscape
    var id: String { rawValue }
}

enum WindowGeometryPreset: String, CaseIterable, Identifiable {
    case compactPortrait, tallPortrait, square, landscapeVideo, leftRail, rightRail, large
    var id: String { rawValue }

    var title: String {
        switch self {
        case .compactPortrait: return "Compact portrait"
        case .tallPortrait: return "Tall portrait"
        case .square: return "Square"
        case .landscapeVideo: return "Landscape video"
        case .leftRail: return "Left rail"
        case .rightRail: return "Right rail"
        case .large: return "Large"
        }
    }
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
    var launchWindowed: Bool = true

    mutating func apply(_ preset: WindowGeometryPreset) {
        switch preset {
        case .compactPortrait:
            width = 320; height = 560; x = 35; y = 120; orientation = .portrait
        case .tallPortrait:
            width = 360; height = 720; x = 15; y = 60; orientation = .portrait
        case .square:
            width = 390; height = 390; x = 0; y = 180; orientation = .automatic
        case .landscapeVideo:
            width = 720; height = 405; x = 0; y = 120; orientation = .landscape
        case .leftRail:
            width = 300; height = 720; x = 0; y = 60; orientation = .portrait
        case .rightRail:
            width = 300; height = 720; x = 90; y = 60; orientation = .portrait
        case .large:
            width = 390; height = 760; x = 0; y = 35; orientation = .automatic
        }
    }
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published var profiles: [String: AppWindowProfile] = [:]
    private let key = "niga.windowProfiles"

    init() { load() }

    func profile(for bundleID: String) -> AppWindowProfile {
        profiles[bundleID] ?? AppWindowProfile(bundleID: bundleID)
    }

    func save(_ profile: AppWindowProfile) {
        profiles[profile.bundleID] = profile
        persist()
    }

    func reset(_ bundleID: String) {
        profiles.removeValue(forKey: bundleID)
        persist()
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }

    private func load() {
        if let d = UserDefaults.standard.data(forKey: key),
           let p = try? JSONDecoder().decode([String: AppWindowProfile].self, from: d) {
            profiles = p
        }
    }
}
