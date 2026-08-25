import Foundation

enum WindowCapability: String, CaseIterable, Identifiable, Codable, Hashable {
    case stageManager = "qeaj75wk3HF4DwQ8qbIi7g"
    case capA = "mG0AnH/Vy1veoqoLRAIgTA"
    case capB = "UCG5MkVahJxG1YULbbd5Bg"
    case capC = "ZYqko/XM5zD3XBfN5RmaXA"
    case capD = "nVh/gwNpy7Jv1NOk00CMrw"
    case capE = "uKc7FPnEO++lVhHWHFlGbQ"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stageManager: return "Stage Manager capability"
        case .capA: return "iPad window capability A"
        case .capB: return "iPad window capability B"
        case .capC: return "iPad window capability C"
        case .capD: return "iPad window capability D"
        case .capE: return "iPad window capability E"
        }
    }
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
