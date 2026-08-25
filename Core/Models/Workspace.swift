import Foundation
import Combine

struct WorkspacePreset: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var bundleIDs: [String]
    var profiles: [String: AppWindowProfile]
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var workspaces: [WorkspacePreset] = []
    private let key = "niga.workspaces"

    init() { load() }

    func add(name: String, bundleIDs: [String], profileStore: ProfileStore) {
        let profiles = Dictionary(uniqueKeysWithValues: bundleIDs.map { ($0, profileStore.profile(for: $0)) })
        workspaces.append(WorkspacePreset(name: name, bundleIDs: bundleIDs, profiles: profiles))
        persist()
    }

    func delete(at offsets: IndexSet) {
        workspaces.remove(atOffsets: offsets)
        persist()
    }

    func update(_ workspace: WorkspacePreset) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        workspaces[index] = workspace
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(workspaces) { UserDefaults.standard.set(data, forKey: key) }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WorkspacePreset].self, from: data) else { return }
        workspaces = decoded
    }
}
