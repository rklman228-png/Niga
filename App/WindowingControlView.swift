import SwiftUI

struct WindowingControlView: View {
    @EnvironmentObject var gestalt: GestaltManager
    @EnvironmentObject var springboard: SpringBoardWindowingManager
    @EnvironmentObject var scanner: AppContainerScanner
    @EnvironmentObject var profiles: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var error: String?
    @State private var selectedApp: InstalledContainer?
    @State private var showCanaryConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    statusRow("MobileGestalt", detail: gestalt.status, ok: gestalt.granted)
                    statusRow("SpringBoardServices", detail: springboard.status, ok: springboard.granted)

                    HStack {
                        Text("Raw DeviceClassNumber")
                        Spacer()
                        Text(gestalt.rawDeviceClassNumber.map(String.init) ?? "unavailable")
                            .font(.subheadline.monospaced().weight(.semibold))
                            .foregroundStyle(gestalt.rawDeviceClassNumber == 1 ? Color.green : (gestalt.rawDeviceClassNumber == nil ? Color.secondary : Color.red))
                    }

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
                                    .foregroundStyle(springboard.mode == .stageManager ? Color.red : Color.primary)
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
                    .disabled(!gestalt.granted || !springboard.granted || springboard.requestInFlight || gestalt.deviceClassCanaryArmed)

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
                    .disabled(!springboard.granted || springboard.requestInFlight || gestalt.deviceClassCanaryArmed)

                    Button {
                        resetWindowLayout()
                    } label: {
                        Label("Reset SpringBoard window layout", systemImage: "rectangle.3.group.bubble")
                    }
                    .disabled(!springboard.granted || springboard.requestInFlight || gestalt.deviceClassCanaryArmed)

                    VStack(alignment: .leading, spacing: 5) {
                        Label("Stage Manager mode 2 remains disabled", systemImage: "exclamationmark.shield.fill")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text("The mode-2 test coincided with an abnormally long restart. We already have a better lead now, so there is no reason to dispatch mode 2 again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("DeviceClass cold-start canary") {
                    if gestalt.deviceClassCanaryLastEffective == 2 {
                        Label("PASS — raw iPad class maps to effective SpringBoard class 2", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                    } else if let observed = gestalt.deviceClassCanaryLastEffective {
                        Label("Canary returned effective class \(observed)", systemImage: "xmark.octagon.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                    }

                    Text(gestalt.deviceClassCanaryStatus)
                        .font(.caption)
                        .foregroundStyle(gestalt.deviceClassCanaryArmed ? .red : .secondary)

                    Text("This test does NOT restart SpringBoard. It temporarily writes the same raw DeviceClassNumber used by current iPadOS-mode tweaks (iPhone 1 → iPad 3), closes only Niga, measures SBFEffectiveDeviceClass in a fresh Niga process, restores raw class 1 immediately, then closes Niga once more so the next launch is clean.")
                        .font(.footnote)

                    Button {
                        showCanaryConfirm = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Run DeviceClass canary", systemImage: "testtube.2")
                                .font(.headline)
                            Text("Niga will close. Reopen it; it will measure + restore and close again. Reopen a second time to read the result.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!gestalt.granted || gestalt.deviceClassCanaryArmed || gestalt.rawDeviceClassNumber != 1)

                    Button(role: .destructive) {
                        do {
                            try gestalt.forceRestorePhoneDeviceClass()
                            springboard.refreshGateProbe()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    } label: {
                        Label("Force restore raw iPhone class (1)", systemImage: "cross.case.fill")
                    }
                    .disabled(!gestalt.granted)

                    Text("Do not reboot the phone while the canary is armed. Automatic recovery runs at the very start of the next Niga launch; the force-restore button is the fallback if that recovery ever reports an error.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Section("Hard gate found") {
                    Text("Your v0.9 result confirms the chain: SpringBoard acknowledges mode 1, but SBFEffectiveDeviceClass is phone-class and SBFIsFlexibleWindowingUIAvailable is false. The restore-image code then forces a single-app context because SBPlatformController has zero Medusa capability.")
                        .font(.footnote)

                    Text("The probe below runs inside Niga, not inside SpringBoard. v1.0 also checks whether Apple's native FBSSystemService + SBSRelaunchAction route exists, but it does not invoke that relaunch route yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Refresh hard-gate + relaunch probe") {
                        springboard.refreshGateProbe()
                    }

                    Text(springboard.gateDetails)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }

                Section("Next step after a passing canary") {
                    Text("If the canary reports effective class 2 while raw DeviceClassNumber is back at 1, we have proven the lower-layer gate can be crossed. The next build can combine that temporary class with a native SpringBoard-only relaunch attempt, then restore the phone class instead of globally leaving iPadOS identity enabled.")
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
                if !gestalt.deviceClassCanaryArmed {
                    gestalt.refresh()
                    springboard.connect()
                }
            }
            .sheet(item: $selectedApp) { app in
                QuickWindowAppView(app: app)
                    .environmentObject(profiles)
            }
            .alert("Run DeviceClass canary?", isPresented: $showCanaryConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Run canary") {
                    do {
                        try gestalt.runDeviceClassCanary()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            } message: {
                Text("SpringBoard will NOT be restarted. Niga will write raw class 3, verify it, and close. Reopen Niga immediately. On that launch it measures the effective class, restores raw class 1, verifies recovery, and closes again. Reopen once more for the result. Do not reboot between those launches.")
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
