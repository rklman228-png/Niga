import Foundation

@MainActor
enum LiveSceneController {
    static func apply(_ profile: AppWindowProfile) -> String {
        let orientation: Int32
        switch profile.orientation {
        case .automatic: orientation = 0
        case .portrait: orientation = 1
        case .landscape: orientation = 3
        }

        let ptr = profile.bundleID.withCString { bundleID in
            niga_scene_apply_profile(
                bundleID,
                profile.x,
                profile.y,
                profile.width,
                profile.height,
                orientation,
                profile.alwaysOnTop
            )
        }
        guard let ptr else { return "{\"error\":\"Scene controller returned no data\"}" }
        defer { niga_scene_control_free(ptr) }
        return String(cString: ptr)
    }
}
