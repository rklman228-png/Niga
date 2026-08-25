import SwiftUI

struct WindowingControlView: View {
    @EnvironmentObject var gestalt: GestaltManager
    @EnvironmentObject var springboard: SpringBoardWindowingManager
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
                                    .foregroundStyle(springboard.mode == .stageManager ? .red : .primary)
                                Text(date, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if springboard.mode == .stageManager {
                            Label("Stage Manager was the last acknowledged mode. Use Return to stock full-screen below before more experiments.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
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

                Section("Safe Windowed Apps test") {
                    Button {
                        applyWindowedApps()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Enable Windowed Apps (mode 1)", systemImage: "macwindow.on.rectangle")
                                .font(.headline)
                            Text("Keeps the iPad identity override off, applies the phone-safe MobileGestalt capability set, and asks SpringBoard itself for Windowed Apps. No forced respring.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!gestalt.granted || !springboard.granted || springboard.requestInFlight)

                    Button(role: .destructive) {
                        restoreFullScreen()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Return to stock full-screen (mode 0)", systemImage: "arrow.uturn.backward")
                                .font(.headline)
                            Text("Asks SpringBoard for stock full-screen mode and clears Niga's phone-safe MobileGestalt experiment flags. No forced respring.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!springboard.granted || springboard.requestInFlight)

                    Button {
                        resetWindowLayout()
                    } label: {
                        Label("Reset SpringBoard window layout", systemImage: "rectangle.3.group.bubble")
                    }
                    .disabled(!springboard.granted || springboard.requestInFlight)

                    VStack(alignment: .leading, spacing: 5) {
                        Label("Stage Manager mode 2 disabled in v0.9", systemImage: "exclamationmark.shield.fill")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text("The mode-2 test coincided with an abnormally long restart on the target device. Niga will not dispatch mode 2 from this screen while we isolate the real gate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Hard gate found") {
                    Text("The restore-image SpringBoard code shows a second gate after the mode preference: SBWindowScene asks SBPlatformController whether the device is Medusa-capable. SBPlatformController zeros its Medusa capabilities unless SBFEffectiveDeviceClass() is iPad-class (2). If that gate is false, the switcher falls straight back to single-app context even when mode 1 was acknowledged.")
                        .font(.footnote)

                    Text("The probe below runs inside Niga, not inside SpringBoard, so it is diagnostic evidence rather than a claim that both processes see identical values.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Refresh hard-gate probe") {
                        springboard.refreshGateProbe()
                    }

                    Text(springboard.gateDetails)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }

                Section("What to do after an ACK") {
                    Text("Do not use the old forced WebKit respring. v0.9 intentionally performs no automatic restart. If we need to test a fresh SpringBoard initialization, use a normal iPhone restart from iOS after noting the ACK/probe result here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                if case .failure(let failure) = result {
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
