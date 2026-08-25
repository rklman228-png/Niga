import Foundation

enum WindowCapability: String, CaseIterable, Identifiable, Codable, Hashable {
    case stageManager = "qeaj75wk3HF4DwQ8qbIi7g"
    case medusaFloatingLiveApp = "mG0AnH/Vy1veoqoLRAIgTA"
    case medusaOverlayApp = "UCG5MkVahJxG1YULbbd5Bg"
    case medusaPinnedApp = "ZYqko/XM5zD3XBfN5RmaXA"
    case medusaPIP = "nVh/gwNpy7Jv1NOk00CMrw"
    case ipadIdentity = "uKc7FPnEO++lVhHWHFlGbQ"

    var id: String { rawValue }

    static let phoneSafeWindowing: [WindowCapability] = [
        .stageManager,
        .medusaFloatingLiveApp,
        .medusaOverlayApp,
        .medusaPinnedApp,
        .medusaPIP
    ]

    var title: String {
        switch self {
        case .stageManager: return "Stage Manager capability"
        case .medusaFloatingLiveApp: return "Medusa floating live apps"
        case .medusaOverlayApp: return "Medusa overlay apps"
        case .medusaPinnedApp: return "Medusa pinned apps"
        case .medusaPIP: return "Medusa PiP/mirroring"
        case .ipadIdentity: return "UNSAFE: iPad identity flag"
        }
    }

    var phoneSafe: Bool { self != .ipadIdentity }
}

enum WindowPreset: String, CaseIterable, Identifiable {
    case stageOnly, phoneWindowing, clearWindowing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stageOnly: return "Stage Manager only"
        case .phoneWindowing: return "Phone-preserving native windows"
        case .clearWindowing: return "Restore window capability flags"
        }
    }
}
