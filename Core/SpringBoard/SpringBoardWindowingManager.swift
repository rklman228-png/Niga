import Foundation
import Combine

enum SpringBoardWindowingMode: Int, CaseIterable, Identifiable {
    case fullScreen = 0
    case windowedApps = 1
    case stageManager = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .fullScreen: return "Full Screen Apps"
        case .windowedApps: return "Windowed Apps"
        case .stageManager: return "Stage Manager"
        }
    }

    var detail: String {
        switch self {
        case .fullScreen:
            return "Stock full-screen mode."
        case .windowedApps:
            return "Apple's free-resizable Windowed Apps mode."
        case .stageManager:
            return "Apple's Stage Manager mode."
        }
    }
}

@MainActor
final class SpringBoardWindowingManager: ObservableObject {
    static let shared = SpringBoardWindowingManager()

    private static let lastModeKey = "Niga.LastSpringBoardWindowingMode"
    private static let lastAckKey = "Niga.LastSpringBoardWindowingAck"

    @Published var granted = false
    @Published var status = "SpringBoard service not probed"
    @Published var mode: SpringBoardWindowingMode = .fullScreen
    @Published var requestInFlight = false
    @Published var lastResult = "No SpringBoard request sent yet."
    @Published var serviceDetails = "Not probed"
    @Published var gateDetails = "Hard-gate probe not run yet"
    @Published var hasAcknowledgedMode = false
    @Published var lastAcknowledgedAt: Date?

    private var requestGeneration = 0

    private init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.object(forKey: Self.lastModeKey) as? NSNumber,
           let savedMode = SpringBoardWindowingMode(rawValue: saved.intValue) {
            mode = savedMode
            hasAcknowledgedMode = true
        }
        lastAcknowledgedAt = defaults.object(forKey: Self.lastAckKey) as? Date
    }

    func connect() {
        granted = niga_sbs_windowing_service_available()
        serviceDetails = copyDiagnostics()
        gateDetails = copyGateDiagnostics()
        if granted {
            status = hasAcknowledgedMode
                ? "SpringBoard service ready · last ack: \(mode.title)"
                : "SpringBoard windowing service ready"
        } else {
            status = "SpringBoard windowing service unavailable"
        }
    }

    func refresh() {
        connect()
    }

    func refreshGateProbe() {
        gateDetails = copyGateDiagnostics()
    }

    func apply(_ newMode: SpringBoardWindowingMode,
               completion: @escaping (Result<Void, Error>) -> Void) {
        if !granted { connect() }
        guard granted else {
            completion(.failure(serviceError("SBSRequestUpdateSwitcherWindowingMode is unavailable on this build")))
            return
        }
        guard !requestInFlight else {
            completion(.failure(serviceError("A SpringBoard windowing request is already in flight")))
            return
        }

        requestGeneration += 1
        let generation = requestGeneration
        requestInFlight = true
        status = "Asking SpringBoard for \(newMode.title)…"
        lastResult = "Request dispatched: mode=\(newMode.rawValue) (\(newMode.title))"

        niga_sbs_request_windowing_mode(Int32(newMode.rawValue)) { [weak self] completed in
            DispatchQueue.main.async {
                guard let self, generation == self.requestGeneration, self.requestInFlight else { return }
                self.requestInFlight = false
                if completed {
                    self.mode = newMode
                    self.hasAcknowledgedMode = true
                    self.lastAcknowledgedAt = Date()
                    UserDefaults.standard.set(newMode.rawValue, forKey: Self.lastModeKey)
                    UserDefaults.standard.set(self.lastAcknowledgedAt, forKey: Self.lastAckKey)
                    self.status = "SpringBoard acknowledged \(newMode.title)"
                    self.lastResult = "SpringBoardServices completion received for mode \(newMode.rawValue). No forced respring was performed."
                    self.refreshGateProbe()
                    completion(.success(()))
                } else {
                    self.status = "SpringBoard request failed"
                    self.lastResult = "The SpringBoardServices bridge could not dispatch/complete mode \(newMode.rawValue).\n\n\(self.copyDiagnostics())"
                    completion(.failure(self.serviceError("SpringBoard did not acknowledge the windowing request")))
                }
            }
        }

        // A blocked service connection otherwise looks like a forever spinner.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self, generation == self.requestGeneration, self.requestInFlight else { return }
            self.requestInFlight = false
            self.status = "SpringBoard request timed out"
            self.lastResult = "No completion arrived from SpringBoard within 4 seconds. The symbol exists, but the service request was not acknowledged by this signed process.\n\n\(self.copyDiagnostics())"
            completion(.failure(self.serviceError("SpringBoardServices request timed out")))
        }
    }

    func resetLayout(completion: @escaping (Result<Void, Error>) -> Void) {
        if !granted { connect() }
        guard granted else {
            completion(.failure(serviceError("SpringBoard windowing service unavailable")))
            return
        }
        guard !requestInFlight else {
            completion(.failure(serviceError("A SpringBoard request is already in flight")))
            return
        }

        requestGeneration += 1
        let generation = requestGeneration
        requestInFlight = true
        status = "Requesting layout reset…"

        niga_sbs_request_reset_layout { [weak self] completed in
            DispatchQueue.main.async {
                guard let self, generation == self.requestGeneration, self.requestInFlight else { return }
                self.requestInFlight = false
                if completed {
                    self.status = "SpringBoard reset window layout"
                    self.lastResult = "SBSRequestResetLayoutAttributes completed successfully."
                    completion(.success(()))
                } else {
                    self.status = "Layout reset failed"
                    self.lastResult = "SpringBoard did not acknowledge SBSRequestResetLayoutAttributes."
                    completion(.failure(self.serviceError("SpringBoard did not acknowledge the layout reset")))
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self, generation == self.requestGeneration, self.requestInFlight else { return }
            self.requestInFlight = false
            self.status = "Layout reset timed out"
            self.lastResult = "No completion arrived for SBSRequestResetLayoutAttributes within 4 seconds."
            completion(.failure(self.serviceError("SpringBoard layout reset timed out")))
        }
    }

    var headerStatus: String {
        if requestInFlight { return "Switching…" }
        if !granted { return "SBS unavailable" }
        if hasAcknowledgedMode { return mode.title }
        return "SBS ready"
    }

    private func copyDiagnostics() -> String {
        guard let ptr = niga_sbs_copy_diagnostics() else { return "No diagnostics" }
        defer { niga_sbs_free_string(ptr) }
        return String(cString: ptr)
    }

    private func copyGateDiagnostics() -> String {
        guard let ptr = niga_sbs_copy_gate_diagnostics() else { return "No hard-gate diagnostics" }
        defer { niga_sbs_free_string(ptr) }
        return String(cString: ptr)
    }

    private func serviceError(_ message: String) -> NSError {
        NSError(
            domain: "Niga.SpringBoardServices",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
