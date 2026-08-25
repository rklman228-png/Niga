import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject var gestalt: GestaltManager
    @EnvironmentObject var respring: RespringController
    @EnvironmentObject var scanner: AppContainerScanner
    @EnvironmentObject var profiles: ProfileStore
    @EnvironmentObject var workspaces: WorkspaceStore
    @EnvironmentObject var experiments: ExperimentLog
    @State private var error: String?
    @State private var selectedApp: InstalledContainer?

    var body: some View {
        TabView {
            NavigationStack { windowLab }
                .tabItem { Label("Windows", systemImage: "rectangle.3.group") }
            NavigationStack { appsLab }
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            NavigationStack { WorkspaceListView() }
                .tabItem { Label("Spaces", systemImage: "rectangle.3.group.fill") }
            NavigationStack { SystemExplorerView() }
                .tabItem { Label("System", systemImage: "externaldrive.connected.to.line.below") }
            NavigationStack { SceneProbeView() }
                .tabItem { Label("Probe", systemImage: "waveform.path.ecg.rectangle") }
            NavigationStack { toolsLab }
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
        }
        .alert("Niga", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: {
            Text(error ?? "")
        }
        .sheet(item: $selectedApp) { app in ProfileEditor(app: app) }
    }

    private var windowLab: some View {
        Form {
            Section("Access") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gestalt.status)
                        Text(gestalt.identityGuard)
                            .font(.caption)
                            .foregroundStyle(gestalt.values[.ipadIdentity] == true ? .red : .secondary)
                    }
                    Spacer()
                    Circle().fill(gestalt.granted ? Color.green : Color.secondary).frame(width: 10, height: 10)
                }
                Button("Run sandbox escape") { gestalt.connect() }
            }

            Section("One-tap phone windowing") {
                Button("Apply phone-safe windows") {
                    run { try gestalt.applyExperiment(.stageAllMedusa) }
                }
                .disabled(!gestalt.granted)

                Button("Apply + Respring") {
                    runAndRespring { try gestalt.applyExperiment(.stageAllMedusa) }
                }
                .fontWeight(.semibold)
                .disabled(!gestalt.granted)

                Text("Never changes DeviceClassNumber and always removes the iPad identity override first. Apps should continue seeing an iPhone while SpringBoard gets the multitasking capabilities.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Capability isolation matrix") {
                ForEach(WindowExperimentPreset.allCases) { preset in
                    Button {
                        run { try gestalt.applyExperiment(preset) }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preset.title)
                            Text(preset.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!gestalt.granted)
                }
                Text("Apply one preset → Respring → test resizing/multiple apps → record the result. This isolates the minimum set instead of turning the whole phone into an iPad.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Individual phone-safe capabilities") {
                ForEach(WindowCapability.allCases.filter(\.phoneSafe)) { cap in
                    Toggle(cap.title, isOn: Binding(
                        get: { gestalt.values[cap] ?? false },
                        set: { value in run { try gestalt.set(cap, enabled: value) } }
                    ))
                    .disabled(!gestalt.granted)
                }
            }

            Section("Unsafe identity lab") {
                Toggle(WindowCapability.ipadIdentity.title, isOn: Binding(
                    get: { gestalt.values[.ipadIdentity] ?? false },
                    set: { value in run { try gestalt.set(.ipadIdentity, enabled: value) } }
                ))
                .tint(.red)
                .disabled(!gestalt.granted)
                Text("This is the flag we deliberately avoid. Full iPadOS mode also changes DeviceClassNumber; Niga's phone-safe presets never touch that field.")
                    .font(.footnote).foregroundStyle(.red)
            }

            Section("Experiment log") {
                Button("Record current capability set") { experiments.capture(enabled: gestalt.values) }
                NavigationLink("Open experiment history") { ExperimentHistoryView() }
            }

            Section("Apply") {
                Button("Respring now") { respring.respring() }
                    .fontWeight(.semibold)
                Text("Use this after MobileGestalt changes before judging the result.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Window Lab")
        .toolbar { Button("Refresh") { gestalt.refresh() } }
    }

    private var appsLab: some View {
        List {
            Section {
                Button("Scan app containers") { scanner.scan() }
                Text(scanner.status).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(scanner.apps) { app in
                Button { selectedApp = app } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.displayName)
                        Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Apps")
    }

    private var toolsLab: some View {
        List {
            Section("MobileGestalt diff") {
                Button("Create snapshot") { run { _ = try gestalt.snapshot(name: "manual") } }
                Button("Diff current vs snapshot") { run { try gestalt.diffAgainstLatestBackup() } }
                NavigationLink("Show diff") {
                    List(gestalt.lastDiff, id: \.self) { line in
                        Text(line).font(.caption.monospaced()).textSelection(.enabled)
                    }.navigationTitle("Gestalt Diff")
                }
            }

            Section("Recovery") {
                Button("Restore original MobileGestalt", role: .destructive) {
                    run { try gestalt.restoreOriginal() }
                }
                Button("Restore original + Respring", role: .destructive) {
                    runAndRespring { try gestalt.restoreOriginal() }
                }
                Button("Respring") { respring.respring() }
                NavigationLink("All backups") { BackupListView() }
            }
        }
        .navigationTitle("Tools")
    }

    private func run(_ work: () throws -> Void) {
        do { try work() } catch { self.error = error.localizedDescription }
    }

    private func runAndRespring(_ work: () throws -> Void) {
        do {
            try work()
            respring.respring()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct BackupListView: View {
    @EnvironmentObject var gestalt: GestaltManager
    @EnvironmentObject var respring: RespringController
    @State private var error: String?

    var body: some View {
        List(gestalt.backups, id: \.self) { url in
            VStack(alignment: .leading) {
                Text(url.lastPathComponent).font(.caption)
                HStack {
                    Button("Restore") { restore(url, respring: false) }
                    Button("Restore + Respring") { restore(url, respring: true) }
                }
            }
        }
        .navigationTitle("Backups")
        .alert("Restore", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private func restore(_ url: URL, respring shouldRespring: Bool) {
        do {
            try gestalt.restore(url)
            if shouldRespring { respring.respring() }
        } catch { self.error = error.localizedDescription }
    }
}

struct ProfileEditor: View {
    @EnvironmentObject var profiles: ProfileStore
    let app: InstalledContainer
    @State private var profile: AppWindowProfile
    @Environment(\.dismiss) private var dismiss

    init(app: InstalledContainer) {
        self.app = app
        _profile = State(initialValue: AppWindowProfile(bundleID: app.bundleID))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(app.bundleID) {
                    Picker("Orientation", selection: $profile.orientation) {
                        ForEach(WindowOrientation.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Stepper("Width: \(Int(profile.width))", value: $profile.width, in: 180...1200, step: 10)
                    Stepper("Height: \(Int(profile.height))", value: $profile.height, in: 180...1600, step: 10)
                    Stepper("X: \(Int(profile.x))", value: $profile.x, in: -900...1600, step: 10)
                    Stepper("Y: \(Int(profile.y))", value: $profile.y, in: -900...2000, step: 10)
                    Toggle("Always on top", isOn: $profile.alwaysOnTop)
                    Toggle("Launch windowed", isOn: $profile.launchWindowed)
                }

                Section("Geometry presets") {
                    ForEach(WindowGeometryPreset.allCases) { preset in
                        Button(preset.title) { profile.apply(preset) }
                    }
                }

                Section("Actions") {
                    Button("Launch app") { _ = AppLauncher.open(bundleID: app.bundleID) }
                    NavigationLink("Probe FrontBoard scene access") {
                        SceneProbeView(initialBundleID: app.bundleID)
                    }
                    NavigationLink("Browse data container") {
                        ContainerBrowserView(url: URL(fileURLWithPath: app.path, isDirectory: true))
                    }
                }

                Section("Per-app orientation") {
                    Text("The profile already stores independent orientation and geometry. The Scene Probe now dumps the exact private scene/update API surface and signing entitlements on this beta so enforcement can attach to the route that actually survives sideload signing instead of globally spoofing iPad identity.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(app.displayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { profile = AppWindowProfile(bundleID: app.bundleID) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { profiles.save(profile); dismiss() }
                }
            }
            .onAppear { profile = profiles.profile(for: app.bundleID) }
        }
    }
}

struct SceneProbeView: View {
    @StateObject private var probe = SceneProbeModel()
    private let initialBundleID: String

    init(initialBundleID: String = "") {
        self.initialBundleID = initialBundleID
    }

    var body: some View {
        List {
            Section("Target") {
                TextField("Bundle ID, e.g. com.apple.mobilesafari", text: $probe.bundleID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(probe.running ? "Probing…" : "Run scene/API probe") { probe.run() }
                    .disabled(probe.running)
                Text("Open the target app once first for the running-process handle test. The probe is read-only: it also reports current iPhone idiom, scene geometry, private class methods and the entitlements that survived signing.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Report") {
                Text(probe.report)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Scene Probe")
        .onAppear {
            if probe.bundleID.isEmpty && !initialBundleID.isEmpty { probe.bundleID = initialBundleID }
        }
    }
}

struct ContainerBrowserView: View {
    let url: URL
    @StateObject private var service = ContainerFileService()
    @State private var preview: ContainerEntry?
    @State private var replacementTarget: ContainerEntry?
    @State private var showImporter = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Text(url.path).font(.caption2.monospaced()).textSelection(.enabled)
                Text(service.status).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(service.entries) { entry in
                if entry.isDirectory {
                    NavigationLink {
                        ContainerBrowserView(url: entry.url)
                    } label: {
                        Label(entry.name, systemImage: "folder")
                    }
                } else {
                    Button { preview = entry } label: {
                        Label(entry.name, systemImage: "doc")
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Replace file…") {
                            replacementTarget = entry
                            showImporter = true
                        }
                        Button("Delete", role: .destructive) {
                            do { try service.delete(entry.url); service.list(url) }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }
        }
        .navigationTitle(url.lastPathComponent.isEmpty ? "Container" : url.lastPathComponent)
        .onAppear { service.list(url) }
        .sheet(item: $preview) { FilePreviewView(entry: $0) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
            guard let target = replacementTarget else { return }
            do {
                let source = try result.get()
                try service.replaceFile(target: target.url, with: source)
                service.list(url)
            } catch { self.error = error.localizedDescription }
        }
        .alert("File operation", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }
}

struct FilePreviewView: View {
    let entry: ContainerEntry
    @StateObject private var service = ContainerFileService()
    @State private var text = "Loading…"

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(entry.name)
            .task {
                do { text = try service.readText(entry.url) }
                catch { text = error.localizedDescription }
            }
        }
    }
}

struct WorkspaceListView: View {
    @EnvironmentObject var workspaces: WorkspaceStore
    @State private var builder = false

    var body: some View {
        List {
            ForEach(workspaces.workspaces) { workspace in
                NavigationLink {
                    WorkspaceDetailView(workspace: workspace)
                } label: {
                    VStack(alignment: .leading) {
                        Text(workspace.name)
                        Text("\(workspace.bundleIDs.count) apps").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: workspaces.delete)
        }
        .navigationTitle("Workspaces")
        .toolbar { Button("New") { builder = true } }
        .sheet(isPresented: $builder) { WorkspaceBuilderView() }
    }
}

struct WorkspaceBuilderView: View {
    @EnvironmentObject var scanner: AppContainerScanner
    @EnvironmentObject var profiles: ProfileStore
    @EnvironmentObject var workspaces: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Workspace"
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name", text: $name)
                    if scanner.apps.isEmpty { Button("Scan apps") { scanner.scan() } }
                }
                ForEach(scanner.apps) { app in
                    Button {
                        if selected.contains(app.bundleID) { selected.remove(app.bundleID) }
                        else { selected.insert(app.bundleID) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(app.displayName)
                                Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selected.contains(app.bundleID) { Image(systemName: "checkmark.circle.fill") }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("New Workspace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        workspaces.add(name: name, bundleIDs: Array(selected).sorted(), profileStore: profiles)
                        dismiss()
                    }.disabled(selected.isEmpty)
                }
            }
        }
    }
}

struct WorkspaceDetailView: View {
    @EnvironmentObject var profiles: ProfileStore
    let workspace: WorkspacePreset

    var body: some View {
        List {
            Section("Apps") {
                ForEach(workspace.bundleIDs, id: \.self) { bundleID in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(bundleID)
                            if let p = workspace.profiles[bundleID] {
                                Text("\(Int(p.width))×\(Int(p.height)) · \(p.orientation.rawValue)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Open") { _ = AppLauncher.open(bundleID: bundleID) }
                    }
                }
            }
            Section {
                Button("Restore saved profiles") {
                    for profile in workspace.profiles.values { profiles.save(profile) }
                }
                Button("Open all apps") {
                    for bundleID in workspace.bundleIDs { _ = AppLauncher.open(bundleID: bundleID) }
                }
            }
        }
        .navigationTitle(workspace.name)
    }
}

struct ExperimentHistoryView: View {
    @EnvironmentObject var experiments: ExperimentLog

    var body: some View {
        List {
            ForEach($experiments.experiments) { $item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.date.formatted()).font(.caption).foregroundStyle(.secondary)
                    Text(item.enabledKeys.isEmpty ? "No capability keys" : item.enabledKeys.joined(separator: "\n"))
                        .font(.caption2.monospaced()).textSelection(.enabled)
                    Picker("Result", selection: $item.outcome) {
                        ForEach(ExperimentOutcome.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    TextField("Note", text: $item.note)
                    Button("Save result") { experiments.update(item) }
                }
                .padding(.vertical, 4)
            }
            .onDelete(perform: experiments.delete)
        }
        .navigationTitle("Experiments")
    }
}
