import Foundation

actor OPCUAClientRuntime {
    private let id = UUID()
    private var isRunning = false
    private var iterateTask: Task<Void, Never>?
    private var iterationInterval: Duration = .milliseconds(100)
    private var lifecycleEvents: [OPCUARuntimeEvent] = []

    var runtimeId: UUID { id }

    func start(iterationInterval: Duration = .milliseconds(100)) {
        self.iterationInterval = iterationInterval

        guard !isRunning else { return }
        isRunning = true
        record(.started, message: "Runtime started")

        iterateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: iterationInterval)
                await self?.iterateOnce()
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        iterateTask?.cancel()
        iterateTask = nil
        isRunning = false
        record(.stopped, message: "Runtime stopped")
    }

    func snapshot() -> OPCUAClientRuntimeSnapshot {
        OPCUAClientRuntimeSnapshot(
            id: id,
            isRunning: isRunning,
            iterationIntervalMilliseconds: iterationInterval.millisecondsApproximation,
            recentEvents: Array(lifecycleEvents.prefix(20))
        )
    }

    private func iterateOnce() {
        // This actor is the intended ownership boundary for UA_Client_run_iterate.
        // The current SimpleOpcUaClient bridge remains synchronous; integration should move C-client iteration here.
        record(.iteration, message: "Runtime iteration")
    }

    private func record(_ kind: OPCUARuntimeEvent.Kind, message: String) {
        lifecycleEvents.insert(OPCUARuntimeEvent(kind: kind, message: message), at: 0)
        if lifecycleEvents.count > 200 {
            lifecycleEvents.removeLast()
        }
    }
}

struct OPCUAClientRuntimeSnapshot: Hashable {
    let id: UUID
    let isRunning: Bool
    let iterationIntervalMilliseconds: Int
    let recentEvents: [OPCUARuntimeEvent]
}

struct OPCUARuntimeEvent: Identifiable, Hashable {
    let id = UUID()
    let timestamp = Date()
    let kind: Kind
    let message: String

    enum Kind: String, Hashable {
        case started = "Started"
        case stopped = "Stopped"
        case iteration = "Iteration"
        case callback = "Callback"
        case error = "Error"
    }
}

private extension Duration {
    nonisolated var millisecondsApproximation: Int {
        let components = self.components
        let seconds = components.seconds * 1_000
        let attoseconds = components.attoseconds / 1_000_000_000_000_000
        return Int(seconds + attoseconds)
    }
}
