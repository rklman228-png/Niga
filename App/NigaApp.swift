import SwiftUI

@main
struct NigaApp: App {
    @StateObject private var gestalt = GestaltManager.shared
    @StateObject private var respring = RespringController()
    @StateObject private var scanner = AppContainerScanner()
    @StateObject private var profiles = ProfileStore()
    @StateObject private var workspaces = WorkspaceStore()
    @StateObject private var experiments = ExperimentLog()
    @State private var showLiveSceneLab = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(gestalt)
                .environmentObject(respring)
                .environmentObject(scanner)
                .environmentObject(profiles)
                .environmentObject(workspaces)
                .environmentObject(experiments)
                .overlay(alignment: .topTrailing) {
                    Button {
                        showLiveSceneLab = true
                    } label: {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(.top, 4)
                    .padding(.trailing, 8)
                    .accessibilityLabel("Open Live Scene Lab")
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
        }
    }
}
