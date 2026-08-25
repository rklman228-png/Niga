import SwiftUI

struct RootView: View {
    @EnvironmentObject var gestalt: GestaltManager
    @EnvironmentObject var respring: RespringController
    @EnvironmentObject var scanner: AppContainerScanner
    @EnvironmentObject var profiles: ProfileStore
    @State private var error: String?
    @State private var selectedApp: InstalledContainer?

    var body: some View {
        TabView {
            NavigationStack { windowLab }.tabItem { Label("Windows", systemImage: "rectangle.3.group") }
            NavigationStack { appsLab }.tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            NavigationStack { diffLab }.tabItem { Label("Diff", systemImage: "arrow.left.arrow.right") }
            NavigationStack { recovery }.tabItem { Label("Recovery", systemImage: "lifepreserver") }
        }
        .alert("Niga", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
        .sheet(item: $selectedApp) { app in ProfileEditor(app: app) }
    }

    private var windowLab: some View {
        Form {
            Section("Access") {
                HStack { Text(gestalt.status); Spacer(); Circle().fill(gestalt.granted ? Color.green : Color.secondary).frame(width: 10, height: 10) }
                Button("Run sandbox escape") { gestalt.connect() }
            }
            Section("Phone-preserving windowing") {
                Button("Apply native windows preset") { run { try gestalt.apply(.phoneWindowing) } }
                Button("Stage Manager capability only") { run { try gestalt.apply(.stageOnly) } }
                Button("Clear window capability flags", role: .destructive) { run { try gestalt.apply(.clearWindowing) } }
                Text("These presets intentionally do not change the iPhone/iPad device-class field. The goal is to keep apps in iPhone idiom while exposing SpringBoard's native window manager.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Individual capability lab") {
                ForEach(WindowCapability.allCases) { cap in
                    Toggle(cap.title, isOn: Binding(get: { gestalt.values[cap] ?? false }, set: { value in run { try gestalt.set(cap, enabled: value) } }))
                }
            }
            Section("Apply") {
                Button("Respring now") { respring.respring() }.fontWeight(.semibold)
                Text("Respring is required after MobileGestalt changes before judging whether native windowing appeared.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Window Lab").toolbar { Button("Refresh") { gestalt.refresh() } }
    }

    private var appsLab: some View {
        List {
            Section {
                Button("Scan app containers") { scanner.scan() }
                Text(scanner.status).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(scanner.apps) { app in
                Button { selectedApp = app } label: {
                    VStack(alignment: .leading, spacing: 3) { Text(app.displayName); Text(app.bundleID).font(.caption).foregroundStyle(.secondary) }
                }.buttonStyle(.plain)
            }
        }.navigationTitle("Apps")
    }

    private var diffLab: some View {
        List {
            Section {
                Button("Create snapshot") { run { _ = try gestalt.snapshot(name: "manual") } }
                Button("Diff current vs previous") { run { try gestalt.diffAgainstLatestBackup() } }
            }
            Section("CacheExtra changes") { ForEach(gestalt.lastDiff, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) } }
        }.navigationTitle("Diff Lab")
    }

    private var recovery: some View {
        List {
            Section("Emergency") {
                Button("Restore original MobileGestalt", role: .destructive) { run { try gestalt.restoreOriginal() } }
                Button("Respring") { respring.respring() }
            }
            Section("Backups") {
                ForEach(gestalt.backups, id: \.self) { url in
                    Button(url.lastPathComponent) { run { try gestalt.restore(url) } }.font(.caption)
                }
            }
        }.navigationTitle("Recovery")
    }

    private func run(_ work: () throws -> Void) { do { try work() } catch { self.error = error.localizedDescription } }
}

struct ProfileEditor: View {
    @EnvironmentObject var profiles: ProfileStore
    let app: InstalledContainer
    @State private var profile: AppWindowProfile
    @Environment(\.dismiss) private var dismiss

    init(app: InstalledContainer) { self.app = app; _profile = State(initialValue: AppWindowProfile(bundleID: app.bundleID)) }

    var body: some View {
        NavigationStack {
            Form {
                Section(app.bundleID) {
                    Picker("Orientation", selection: $profile.orientation) { ForEach(WindowOrientation.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                    Stepper("Width: \(Int(profile.width))", value: $profile.width, in: 220...900, step: 10)
                    Stepper("Height: \(Int(profile.height))", value: $profile.height, in: 220...1200, step: 10)
                    Toggle("Always on top (research target)", isOn: $profile.alwaysOnTop)
                }
                Section {
                    Button("Launch app") { _ = AppLauncher.open(bundleID: app.bundleID) }
                    Text("Profile storage is live now. Enforcing per-app orientation/position requires the next scene/FrontBoard research layer; the profile is already persisted so the UI does not need to be redesigned later.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(app.displayName)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { profiles.save(profile); dismiss() } } }
            .onAppear { profile = profiles.profile(for: app.bundleID) }
        }
    }
}
