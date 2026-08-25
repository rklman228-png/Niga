import SwiftUI

@main
struct NigaApp: App {
    @StateObject private var gestalt = GestaltManager.shared
    @StateObject private var respring = RespringController()
    @StateObject private var scanner = AppContainerScanner()
    @StateObject private var profiles = ProfileStore()
    @StateObject private var workspaces = WorkspaceStore()
    @StateObject private var experiments = ExperimentLog()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(gestalt)
                .environmentObject(respring)
                .environmentObject(scanner)
                .environmentObject(profiles)
                .environmentObject(workspaces)
                .environmentObject(experiments)
                .fullScreenCover(isPresented: $respring.active) {
                    RespringView().ignoresSafeArea()
                }
        }
    }
}
