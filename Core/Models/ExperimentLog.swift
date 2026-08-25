import Foundation
import Combine

enum ExperimentOutcome: String, Codable, CaseIterable, Identifiable, Hashable {
    case unknown, works, partial, broken
    var id: String { rawValue }
}

struct WindowExperiment: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var enabledKeys: [String]
    var outcome: ExperimentOutcome = .unknown
    var note: String = ""
}

@MainActor
final class ExperimentLog: ObservableObject {
    @Published var experiments: [WindowExperiment] = []
    private let key = "niga.windowExperiments"

    init() { load() }

    func capture(enabled: [WindowCapability: Bool]) {
        let keys = enabled.filter { $0.value }.map { $0.key.rawValue }.sorted()
        experiments.insert(WindowExperiment(enabledKeys: keys), at: 0)
        persist()
    }

    func update(_ item: WindowExperiment) {
        guard let i = experiments.firstIndex(where: { $0.id == item.id }) else { return }
        experiments[i] = item
        persist()
    }

    func delete(at offsets: IndexSet) {
        experiments.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(experiments) { UserDefaults.standard.set(data, forKey: key) }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([WindowExperiment].self, from: data) else { return }
        experiments = items
    }
}
