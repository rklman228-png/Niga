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
            NavigationStack { SceneProbeView() }
                .tabItem { Label("Probe", systemImage: "waveform.path.ecg.rectangle") }
            NavigationStack { diffLab }
                .tabItem { Label("Diff", systemImage: "arrow.left.arrow.right") }
            NavigationStack { recovery }
                .tabItem { Label("Recovery", systemImage: "lifepreserver") }
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
                    Text(gestalt.status)
                    Spacer()
                    Circle().fill(gestalt.granted ? Color.green : Color.secondary).frame(width: 10, height: 10)
                }
                Button("Run sandbox escape") { gestalt.connect() }
            }

            Section("Phone-preserving windowing") {
                Button("Apply native windows preset") { run { try gestalt.apply(.phoneWindowing) } }
                Button("Stage Manager capability only") { run { try gestalt.apply(.stageOnly) } }
                Button("Clear window capability flags", role: .destructive) { run { try gestalt.apply(.clearWindowing) } }
                Text("This path never flips the iPhone/iPad device-class field. We only expose the native window capabilities and keep the phone identity intact.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Individual capability lab") {
                ForEach(WindowCapability.allCases) { cap in
                    Toggle(cap.title, isOn: Binding(
                        get: { gestalt.values[cap] ?? false },
                        set: { value in run { try gestalt.set(cap, enabled: value) } }
                    ))
                }
            }

            Section("Experiment log") {
                Button("Record current capability set") { experiments.capture(enabled: gestalt.values) }
                NavigationLink("Open experiment history") { ExperimentHistoryView() }
            }

            Section("Apply") {
                Button("Respring now") { respring.respring() }
                    .fontWeight(.semibold)
                Text("Respring after MobileGestalt changes before judging whether the native window manager appeared.")
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

    private var diffLab: some View {
        List {
            Section {
                Button("Create snapshot") { run { _ = try gestalt.snapshot(name: "manual") } }
                Button("Diff current vs previous") { run { try gestalt.diffAgainstLatestBackup() } }
            }
            Section("CacheExtra changes") {
                ForEach(gestalt.lastDiff, id: \.self) {
                    Text($0).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Diff Lab")
    }

    private var recovery: some View {
        List {
            Section("Emergency") {
                Button("Restore original MobileGestalt", role: .destructive) { run { try gestalt.restoreOriginal() } }
                Button("Respring") { respring.respring() }
            }
            Section("Backups") {
                ForEach(gestalt.backups, id: \.self) { url in
                    Button(url.lastPathComponent) { run { try gestalt.restore(url) } }
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Recovery")
    }

    private func run(_ work: () throws -> Void) {
        do { try work() } catch { self.error = error.localizedDescription }
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
                    Stepper("Width: \(Int(profile.width))", value: $profile.width, in: 220...900, step: 10)
                    Stepper("Height: \(Int(profile.height))", value: $profile.height, in: 220...1200, step: 10)
                    Stepper("X: \(Int(profile.x))", value: $profile.x, in: -500...1000, step: 10)
                    Stepper("Y: \(Int(profile.y))", value: $profile.y, in: -500...1600, step: 10)
                    Toggle("Always on top", isOn: $profile.alwaysOnTop)
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
                Section {
                    Text("Orientation/geometry are persisted per app now. Scene enforcement is being attached only after the probe proves which FrontBoard/RunningBoard operations survive normal sideload signing on iOS 27 beta 3.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(app.displayName)
            .toolbar {
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
                Button(probe.running ? "Probing…" : "Run read-only scene probe") {
                    probe.run()
                }
                .disabled(probe.running)
                Text("For the running-app handle test, open the target app once first. The probe never creates, resizes, destroys, or modifies its scene.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Report") {
                Text(probe.report)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }
            Section("What we are testing") {
                Text("This checks whether FrontBoard, FrontBoardServices and RunningBoardServices load, whether the private scene classes/selectors exist on your exact beta, whether an RBS process handle can be obtained for an already-running normal app, and which FrontBoard/RunningBoard entitlements the installed Niga signature actually has. If the classes exist but the private entitlements are absent, we know native SpringBoard windowing must be driven through capability/state paths instead of directly manufacturing external scenes.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Scene Probe")
        .onAppear {
            if probe.bundleID.isEmpty && !initialBundleID.isEmpty {
                probe.bundleID = initialBundleID
            }
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
            } catch {
                self.error = error.localizedDescription
            }
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
                Text(text).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
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
    @EnvironmentObject var profiles: ProfileStore
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
