import SwiftUI

@MainActor
final class RespringController: ObservableObject {
    @Published var active = false

    /// v0.8 used a WebKit memory-pressure crash to force a UI restart. On the
    /// target iOS 27 beta that can take a long time and looks dangerously close
    /// to a reboot loop. Keep old call sites harmless: they now open a manual
    /// restart instruction instead of intentionally exhausting memory.
    func respring() {
        active = true
    }
}

struct RespringView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 46))

                Text("Forced respring disabled")
                    .font(.largeTitle.bold())

                Text("Niga no longer uses the WebKit memory-pressure crash from v0.8. It was too aggressive on this iOS 27 beta.")
                    .font(.body)

                Text("If a MobileGestalt experiment needs a fresh SpringBoard start, use a normal iPhone restart from iOS. The Real Windowing screen does not restart the phone automatically anymore.")
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Safe restart")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
