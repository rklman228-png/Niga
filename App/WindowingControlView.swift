import SwiftUI

struct WindowingControlView: View {
    @EnvironmentObject var gestalt: GestaltManager
    @EnvironmentObject var springboard: SpringBoardWindowingManager
    @EnvironmentObject var respring: RespringController
    @EnvironmentObject var scanner: AppContainerScanner
    @EnvironmentObject var profiles: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var error: String?
    @State private var selectedApp: InstalledContainer?

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    statusRow("MobileGestalt", detail: gestalt.status, ok: gestalt.granted)
                    statusRow("SpringBoard prefs", detail: springboard.status, ok: springboard.granted)

                    Button("Reconnect both") {
                        reconnect()
                    }

                    Text("Current system mode: \(springboard.mode.title)")
                        .font(.subheadline.weight(.semibold))
                }

                Section("Actually enable windowing") {
                    Button {
                        applyWindowedApps()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Enable Windowed Apps + Respring", systemImage: "macwindow.on.rectangle")
                                .font(.headline)
                            Text("Turns on the same SpringBoard mode Apple uses for free resizable app windows, while keeping iPhone identity.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        applyStageManager()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Try Stage Manager + Respring", systemImage: "rectangle.3.group")
                            Text("Alternative system mode. This is no longer just a MobileGestalt capability toggle.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(role: .destructive) {
                        restoreFullScreen()
                    } label: {
                        Label("Return to stock full-screen + Respring", systemImage: "arrow.uturn.backward")
                    }
                }

                Section("What was missing in v0.5") {
                    Text("v0.5 enabled device capabilities but never switched SpringBoard's own multitasking mode. This build writes and verifies SBMedusaMultitaskingEnabled / SBChamoisWindowingEnabled using the same mode logic used by Apple's Control Center module, then resprings SpringBoard.")
                        .font(.footnote)
                }

                Section("Open a specific app") {
                    Button("Scan installed app containers") { scanner.scan() }
                    Text(scanner.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ForEach(scanner.apps) { app in
                        Button {
                            selectedApp = app
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.displayName)
                                    Text(app.bundleID)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "macwindow.badge.plus")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("SpringBoard mode bits") {
                    keyRow("SBMedusaMultitaskingEnabled")
                    keyRow("SBChamoisWindowingEnabled")
                    keyRow("SBFlexibleWindowingAutomaticStageCreationEnabledExternal")
                    keyRow("SBWantsManyForegroundWindows")
                    keyRow("SBHasEverUsedMultiAppConfiguration")
                    Text("cfprefsd synchronize: \(springboard.cfprefsSynchronized ? "yes" : "not confirmed")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Recovery") {
                    Button("Restore original SpringBoard prefs", role: .destructive) {
                        run { try springboard.restoreOriginal() }
                    }
                    Button("Restore original SpringBoard prefs + Respring", role: .destructive) {
                        run {
                            try springboard.restoreOriginal()
                            respring.respring()
                        }
                    }
                }
            }
            .navigationTitle("Real Windowing")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                reconnect()
                springboard.refresh()
            }
            .sheet(item: $selectedApp) { app in
                QuickWindowAppView(app: app)
                    .environmentObject(profiles)
            }
            .alert("Niga", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func statusRow(_ title: String, detail: String, ok: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Circle().fill(ok ? Color.green : Color.secondary).frame(width: 10, height: 10)
        }
    }

    private func keyRow(_ key: String) -> some View {
        HStack {
            Text(key).font(.caption2.monospaced())
            Spacer()
            Text((springboard.values[key] ?? false) ? "ON" : "OFF")
                .font(.caption.monospaced().weight(.semibold))
        }
    }

    private func reconnect() {
        if !gestalt.granted { gestalt.connect() }
        if !springboard.granted { springboard.connect() }
        if springboard.granted { springboard.refresh() }
    }

    private func applyWindowedApps() {
        run {
            reconnect()
            guard gestalt.granted else { throw NSError(domain: "Niga", code: 10, userInfo: [NSLocalizedDescriptionKey: gestalt.status]) }
            guard springboard.granted else { throw NSError(domain: "Niga", code: 11, userInfo: [NSLocalizedDescriptionKey: springboard.status]) }
            try gestalt.applyExperiment(.stageAllMedusa)
            try springboard.apply(.windowedApps)
            respring.respring()
        }
    }

    private func applyStageManager() {
        run {
            reconnect()
            guard gestalt.granted else { throw NSError(domain: "Niga", code: 12, userInfo: [NSLocalizedDescriptionKey: gestalt.status]) }
            guard springboard.granted else { throw NSError(domain: "Niga", code: 13, userInfo: [NSLocalizedDescriptionKey: springboard.status]) }
            try gestalt.applyExperiment(.stageAllMedusa)
            try springboard.apply(.stageManager)
            respring.respring()
        }
    }

    private func restoreFullScreen() {
        run {
            reconnect()
            if springboard.granted { try springboard.apply(.fullScreen) }
            if gestalt.granted { try gestalt.applyExperiment(.clear) }
            respring.respring()
        }
    }

    private func run(_ work: () throws -> Void) {
        do { try work() }
        catch { self.error = error.localizedDescription }
    }
}

private struct QuickWindowAppView: View {
    @EnvironmentObject var profiles: ProfileStore
    @Environment(\.dismiss) private var dismiss
    let app: InstalledContainer

    @State private var profile: AppWindowProfile
    @State private var result = LiveSceneController.lastLaunchResult

    init(app: InstalledContainer) {
        self.app = app
        _profile = State(initialValue: AppWindowProfile(bundleID: app.bundleID))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(app.bundleID) {
                    Picker("Orientation", selection: $profile.orientation) {
                        ForEach(WindowOrientation.allCases) { value in
                            Text(value.rawValue.capitalized).tag(value)
                        }
                    }
                    Stepper("Width: \(Int(profile.width))", value: $profile.width, in: 150...1200, step: 10)
                    Stepper("Height: \(Int(profile.height))", value: $profile.height, in: 150...1600, step: 10)
                    Toggle("Always on top", isOn: $profile.alwaysOnTop)
                }

                Section("Presets") {
                    ForEach(WindowGeometryPreset.allCases) { preset in
                        Button(preset.title) { profile.apply(preset) }
                    }
                }

                Section("One tap") {
                    Button {
                        profiles.save(profile)
                        if !LiveSceneController.launchAndApply(profile) {
                            result = LiveSceneController.lastLaunchResult
                        }
                    } label: {
                        Label("Open + force this window", systemImage: "macwindow.badge.plus")
                            .font(.headline)
                    }

                    Text("Niga starts the target app, keeps a short background execution task alive, then attempts the per-app FrontBoard frame/orientation update while the target is foreground. If SpringBoard's Windowed Apps mode is active, this is the direct path into the requested size rather than making you manually return to Niga first.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Last direct-scene result") {
                    Text(result)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                    Button("Refresh result") { result = LiveSceneController.lastLaunchResult }
                }
            }
            .navigationTitle(app.displayName)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .onAppear {
                profile = profiles.profile(for: app.bundleID)
                result = LiveSceneController.lastLaunchResult
            }
        }
    }
}
