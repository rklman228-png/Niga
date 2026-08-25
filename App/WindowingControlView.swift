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
                    statusRow("SpringBoardServices", detail: springboard.status, ok: springboard.granted)

                    if springboard.requestInFlight {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Waiting for SpringBoard acknowledgement…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let date = springboard.lastAcknowledgedAt {
                        HStack {
                            Text("Last acknowledged mode")
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(springboard.mode.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(date, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("No mode has been acknowledged by SpringBoard from this Niga install yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Reconnect SpringBoard service") {
                        springboard.connect()
                    }
                }

                Section("Actually enable windowing") {
                    Button {
                        applyWindowedApps()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Enable Windowed Apps + Respring", systemImage: "macwindow.on.rectangle")
                                .font(.headline)
                            Text("Keeps iPhone identity, enables the phone-safe multitasking capabilities, then asks SpringBoard itself to enter Windowed Apps mode.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!gestalt.granted || !springboard.granted || springboard.requestInFlight)

                    Button {
                        applyStageManager()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Try Stage Manager + Respring", systemImage: "rectangle.3.group")
                                .font(.headline)
                            Text("Same native SpringBoard service, mode 2. The iPad identity override stays off.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!gestalt.granted || !springboard.granted || springboard.requestInFlight)

                    Button(role: .destructive) {
                        restoreFullScreen()
                    } label: {
                        Label("Return to stock full-screen + Respring", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!springboard.granted || springboard.requestInFlight)

                    Button {
                        resetWindowLayout()
                    } label: {
                        Label("Reset SpringBoard window layout", systemImage: "rectangle.3.group.bubble")
                    }
                    .disabled(!springboard.granted || springboard.requestInFlight)
                }

                Section("Why this is different") {
                    Text("v0.6/v0.7 tried to edit SpringBoard preferences on disk. Your DB3 proved that path is outside the sandbox escape we actually have. This build does not need that plist: it calls Apple's own SpringBoardServices requestUpdateSwitcherWindowingMode path, so SpringBoard changes its SBAppSwitcherDefaults itself.")
                        .font(.footnote)
                }

                Section("SpringBoard service diagnostics") {
                    Text(springboard.serviceDetails)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)

                    Text("Last request")
                        .font(.caption.weight(.semibold))
                    Text(springboard.lastResult)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
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

                Section("Apply / Recovery") {
                    Button("Respring now") { respring.respring() }
                        .fontWeight(.semibold)
                    Text("The main mode buttons respring only after the SpringBoardServices completion callback arrives. A timeout/error will leave you here instead of pretending the mode was applied.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Real Windowing")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if !gestalt.granted { gestalt.connect() }
                springboard.connect()
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

    private func applyWindowedApps() {
        do {
            if !gestalt.granted { gestalt.connect() }
            guard gestalt.granted else {
                throw NSError(domain: "Niga", code: 10, userInfo: [NSLocalizedDescriptionKey: gestalt.status])
            }
            try gestalt.applyExperiment(.stageAllMedusa)
            springboard.apply(.windowedApps) { result in
                switch result {
                case .success:
                    respring.respring()
                case .failure(let failure):
                    error = failure.localizedDescription
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func applyStageManager() {
        do {
            if !gestalt.granted { gestalt.connect() }
            guard gestalt.granted else {
                throw NSError(domain: "Niga", code: 12, userInfo: [NSLocalizedDescriptionKey: gestalt.status])
            }
            try gestalt.applyExperiment(.stageAllMedusa)
            springboard.apply(.stageManager) { result in
                switch result {
                case .success:
                    respring.respring()
                case .failure(let failure):
                    error = failure.localizedDescription
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func restoreFullScreen() {
        springboard.apply(.fullScreen) { result in
            switch result {
            case .success:
                do {
                    if gestalt.granted { try gestalt.applyExperiment(.clear) }
                    respring.respring()
                } catch {
                    self.error = error.localizedDescription
                }
            case .failure(let failure):
                error = failure.localizedDescription
            }
        }
    }

    private func resetWindowLayout() {
        springboard.resetLayout { result in
            if case .failure(let failure) = result {
                error = failure.localizedDescription
            }
        }
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

                    Text("Starts the target app and immediately attempts the per-app FrontBoard frame/orientation update. The result below reports whether the frame actually changed, not merely whether the selector returned.")
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
