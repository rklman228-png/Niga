import Foundation

@MainActor
enum AppLauncher {
    static func open(bundleID: String) -> Bool {
        guard let cls = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
              let workspace = cls.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() as? NSObject else { return false }
        let sel = NSSelectorFromString("openApplicationWithBundleID:")
        guard workspace.responds(to: sel) else { return false }
        _ = workspace.perform(sel, with: bundleID)
        return true
    }
}
