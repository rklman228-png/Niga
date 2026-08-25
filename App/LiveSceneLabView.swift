import SwiftUI

struct LiveSceneLabView: View {
    @EnvironmentObject var scanner: AppContainerScanner
    @EnvironmentObject var profiles: ProfileStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Button("Scan app containers") { scanner.scan() }
                Text(scanner.status).font(.footnote).foregroundStyle(.secondary)
            }
            Section("Running-app scene experiments") {
                ForEach(scanner.apps) { app in
                    NavigationLink {
                        LiveSceneAppView(app: app)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.displayName)
                            Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("How to test") {
                Text("Enable phone-safe windowing and respring first. Open the target app once, return to Niga, then try Live Apply. Niga finds the running app's RBS process, looks for a matching FBScene visible to this signed process, and asks FrontBoard to update that scene's frame/orientation. If signing blocks it, the JSON result tells us exactly where the path failed.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Live Scene Lab")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
    }
}

struct LiveSceneAppView: View {
    @EnvironmentObject var profiles: ProfileStore
    let app: InstalledContainer
    @State private var profile: AppWindowProfile
    @State private var result = "Not attempted"

    init(app: InstalledContainer) {
        self.app = app
        _profile = State(initialValue: AppWindowProfile(bundleID: app.bundleID))
    }

    var body: some View {
        Form {
            Section(app.bundleID) {
                Picker("Orientation", selection: $profile.orientation) {
                    ForEach(WindowOrientation.allCases) { orientation in
                        Text(orientation.rawValue.capitalized).tag(orientation)
                    }
                }
                Stepper("Width: \(Int(profile.width))", value: $profile.width, in: 150...1200, step: 10)
                Stepper("Height: \(Int(profile.height))", value: $profile.height, in: 150...1600, step: 10)
                Stepper("X: \(Int(profile.x))", value: $profile.x, in: -900...1600, step: 10)
                Stepper("Y: \(Int(profile.y))", value: $profile.y, in: -900...2000, step: 10)
                Toggle("Always on top (scene level)", isOn: $profile.alwaysOnTop)
            }

            Section("Presets") {
                ForEach(WindowGeometryPreset.allCases) { preset in
                    Button(preset.title) { profile.apply(preset) }
                }
            }

            Section("Run") {
                Button("1 · Open target app") { _ = AppLauncher.open(bundleID: app.bundleID) }
                Button("2 · Try live FrontBoard apply") {
                    profiles.save(profile)
                    result = LiveSceneController.apply(profile)
                }
                .fontWeight(.semibold)
                NavigationLink("Run read-only scene probe") {
                    SceneProbeView(initialBundleID: app.bundleID)
                }
            }

            Section("Result") {
                Text(result).font(.caption2.monospaced()).textSelection(.enabled)
            }

            Section("Important") {
                Text("This route does not spoof the app as iPad. It modifies only the matched external scene. It is intentionally guarded by runtime discovery; on a normal sideload signature, FrontBoard may expose no external scene or reject the update. That failure is useful data for the writable-state fallback.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(app.displayName)
        .onAppear { profile = profiles.profile(for: app.bundleID) }
    }
}
