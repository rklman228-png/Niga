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
        case .medusaPIP: return "Medusa PiP / mirroring"
        case .ipadIdentity: return "UNSAFE: pretend device is iPad"
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

enum WindowExperimentPreset: String, CaseIterable, Identifiable, Codable {
    case stageOnly
    case floatingOnly
    case stageFloating
    case stageFloatingOverlay
    case stageFloatingOverlayPinned
    case stageAllMedusa
    case allMedusaNoStage
    case clear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stageOnly: return "01 · Stage only"
        case .floatingOnly: return "02 · Floating only"
        case .stageFloating: return "03 · Stage + floating"
        case .stageFloatingOverlay: return "04 · + overlay"
        case .stageFloatingOverlayPinned: return "05 · + pinned"
        case .stageAllMedusa: return "06 · Stage + all Medusa"
        case .allMedusaNoStage: return "07 · All Medusa, no Stage"
        case .clear: return "00 · Clear safe flags"
        }
    }

    var detail: String {
        switch self {
        case .stageOnly: return "Tests whether Enhanced Multitasking alone wakes the native window manager."
        case .floatingOnly: return "Tests the floating-live-app capability without Stage Manager."
        case .stageFloating: return "Smallest likely pair for free windows."
        case .stageFloatingOverlay: return "Adds overlay-app support."
        case .stageFloatingOverlayPinned: return "Adds pinned-app support for side-by-side / persistent windows."
        case .stageAllMedusa: return "Full phone-safe set: Stage + floating + overlay + pinned + PiP."
        case .allMedusaNoStage: return "Checks whether Medusa capabilities are enough without Enhanced Multitasking."
        case .clear: return "Removes every phone-safe experiment flag and the unsafe iPad override."
        }
    }

    var enabled: Set<WindowCapability> {
        switch self {
        case .stageOnly: return [.stageManager]
        case .floatingOnly: return [.medusaFloatingLiveApp]
        case .stageFloating: return [.stageManager, .medusaFloatingLiveApp]
        case .stageFloatingOverlay: return [.stageManager, .medusaFloatingLiveApp, .medusaOverlayApp]
        case .stageFloatingOverlayPinned: return [.stageManager, .medusaFloatingLiveApp, .medusaOverlayApp, .medusaPinnedApp]
        case .stageAllMedusa: return Set(WindowCapability.phoneSafeWindowing)
        case .allMedusaNoStage: return [.medusaFloatingLiveApp, .medusaOverlayApp, .medusaPinnedApp, .medusaPIP]
        case .clear: return []
        }
    }
}
