import SwiftUI

@main
struct NigaApp: App {
    @StateObject private var gestalt = GestaltManager.shared
    @StateObject private var respring = RespringController()
    @StateObject private var scanner = AppContainerScanner()
    @StateObject private var profiles = ProfileStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(gestalt)
                .environmentObject(respring)
                .environmentObject(scanner)
                .environmentObject(profiles)
                .fullScreenCover(isPresented: $respring.active) { RespringView().ignoresSafeArea() }
        }
    }
}
