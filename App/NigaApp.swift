import SwiftUI

@main
struct NigaApp: App {
    @StateObject private var gestalt = GestaltManager.shared
    @StateObject private var springboard = SpringBoardWindowingManager.shared
    @StateObject private var respring = RespringController()
    @StateObject private var scanner = AppContainerScanner()
    @StateObject private var profiles = ProfileStore()
    @StateObject private var workspaces = WorkspaceStore()
    @StateObject private var experiments = ExperimentLog()
    @State private var showLiveSceneLab = false
    @State private var showWindowing = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(gestalt)
                .environmentObject(springboard)
                .environmentObject(respring)
                .environmentObject(scanner)
                .environmentObject(profiles)
                .environmentObject(workspaces)
                .environmentObject(experiments)
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack(spacing: 10) {
                        Button {
                            showWindowing = true
                        } label: {
                            Label("REAL WINDOWING", systemImage: "macwindow.on.rectangle")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent)

                        Spacer()

                        HStack(spacing: 5) {
                            if springboard.isDiscovering {
                                ProgressView().controlSize(.mini)
                            } else {
                                Circle()
                                    .fill((gestalt.granted && springboard.granted) ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                            }
                            Text(windowingStatusText)
                                .font(.caption2)
                                .lineLimit(1)
                        }

                        Button {
                            showLiveSceneLab = true
                        } label: {
                            Image(systemName: "bolt.horizontal.circle.fill")
                                .font(.title3)
                        }
                        .accessibilityLabel("Open Live Scene Lab")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.bar)
                }
                .sheet(isPresented: $showWindowing) {
                    WindowingControlView()
                        .environmentObject(gestalt)
                        .environmentObject(springboard)
                        .environmentObject(respring)
                        .environmentObject(scanner)
                        .environmentObject(profiles)
                }
                .sheet(isPresented: $showLiveSceneLab) {
                    NavigationStack {
                        LiveSceneLabView()
                    }
                    .environmentObject(scanner)
                    .environmentObject(profiles)
                }
                .fullScreenCover(isPresented: $respring.active) {
                    RespringView().ignoresSafeArea()
                }
                .task {
                    // Sandbox extensions are process-local and disappear after a
                    // respring/relaunch, so reacquire them every launch. The
                    // SpringBoard resolver performs its slower iOS 27 container
                    // discovery off the main thread when the legacy path is blocked.
                    if !gestalt.granted { gestalt.connect() }
                    if !springboard.granted && !springboard.isDiscovering { springboard.connect() }
                }
        }
    }

    private var windowingStatusText: String {
        if springboard.isDiscovering { return "Resolving prefs…" }
        if springboard.granted { return springboard.mode.title }
        return "Prefs unavailable"
    }
}
