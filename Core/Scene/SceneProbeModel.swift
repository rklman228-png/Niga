import Foundation
import Combine

@MainActor
final class SceneProbeModel: ObservableObject {
    @Published var bundleID = ""
    @Published var report = "No probe run yet."
    @Published var running = false

    func run(bundleID: String? = nil) {
        let target = (bundleID ?? self.bundleID).trimmingCharacters(in: .whitespacesAndNewlines)
        if let bundleID { self.bundleID = bundleID }
        running = true
        defer { running = false }

        let ptr = target.withCString { niga_scene_probe_json($0) }
        guard let ptr else {
            report = "Scene probe returned no data."
            return
        }
        report = String(cString: ptr)
        niga_scene_probe_free(ptr)
    }
}
