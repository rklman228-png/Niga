import Foundation
import UIKit

@MainActor
enum LiveSceneController {
    private static let resultKey = "niga.lastWindowLaunchResult"

    static var lastLaunchResult: String {
        UserDefaults.standard.string(forKey: resultKey) ?? "No one-tap window launch attempted yet."
    }

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
        guard let ptr else {
            let result = "{\"error\":\"Scene controller returned no data\"}"
            UserDefaults.standard.set(result, forKey: resultKey)
            return result
        }
        defer { niga_scene_control_free(ptr) }
        let result = String(cString: ptr)
        UserDefaults.standard.set(result, forKey: resultKey)
        return result
    }

    @discardableResult
    static func launchAndApply(_ profile: AppWindowProfile, delay: TimeInterval = 1.0) -> Bool {
        let application = UIApplication.shared
        var backgroundTask: UIBackgroundTaskIdentifier = .invalid

        backgroundTask = application.beginBackgroundTask(withName: "NigaWindowApply") {
            if backgroundTask != .invalid {
                application.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }

        guard AppLauncher.open(bundleID: profile.bundleID) else {
            let result = "{\"error\":\"Could not launch target app\",\"bundleID\":\"\(profile.bundleID)\"}"
            UserDefaults.standard.set(result, forKey: resultKey)
            if backgroundTask != .invalid {
                application.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
            return false
        }

        // Opening the target backgrounds Niga. A short iOS background task keeps
        // us alive long enough for RunningBoard to expose the target process and
        // for the direct scene resize/orientation attempt to execute.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let result = apply(profile)
            UserDefaults.standard.set(result, forKey: resultKey)
            if backgroundTask != .invalid {
                application.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }
        return true
    }
}
