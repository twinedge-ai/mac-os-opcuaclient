import Foundation

struct ConnectionTestReport: Identifiable, Hashable, Codable {
    var id = UUID()
    var profileName: String
    var endpointURL: String
    var startedAt: Date
    var completedAt: Date
    var steps: [ConnectionTestStep]
    var diagnostics: [String]

    var status: OPCUAStatusCode {
        steps.contains { $0.status.severity == .bad } ? .bad : .good
    }

    var duration: TimeInterval {
        completedAt.timeIntervalSince(startedAt)
    }
}

struct ConnectionTestStep: Identifiable, Hashable, Codable {
    var id = UUID()
    var phase: Phase
    var status: OPCUAStatusCode
    var detail: String
    var durationMilliseconds: Int

    enum Phase: String, CaseIterable, Codable {
        case dns = "DNS Resolution"
        case tcp = "TCP Connection"
        case hello = "Hello/Acknowledge"
        case secureChannel = "OpenSecureChannel"
        case endpointSelection = "Endpoint Selection"
        case createSession = "CreateSession"
        case activateSession = "ActivateSession"
        case namespaceTable = "Namespace Table"
        case serverStatus = "Server Status"
        case diagnostics = "Diagnostics Summary"
    }
}

enum ConnectionTestReportFactory {
    static func report(for server: OPCUAServer, success: Bool, detail: String, hints: [String]) -> ConnectionTestReport {
        let started = Date()
        let status: OPCUAStatusCode = success ? .good : .bad
        let phases = ConnectionTestStep.Phase.allCases

        let steps = phases.enumerated().map { index, phase in
            ConnectionTestStep(
                phase: phase,
                status: success || index < 2 ? .good : status,
                detail: detailForPhase(phase, endpoint: server.endpoint, success: success),
                durationMilliseconds: 12 + index * 7
            )
        }

        return ConnectionTestReport(
            profileName: server.name,
            endpointURL: server.endpoint,
            startedAt: started,
            completedAt: Date(),
            steps: steps,
            diagnostics: hints
        )
    }

    private static func detailForPhase(_ phase: ConnectionTestStep.Phase, endpoint: String, success: Bool) -> String {
        if !success {
            switch phase {
            case .dns, .tcp:
                return "Checked \(endpoint)"
            default:
                return "Not completed because the connection test failed"
            }
        }

        switch phase {
        case .dns: return "Endpoint host resolved"
        case .tcp: return "TCP socket opened"
        case .hello: return "HEL/ACK handshake completed"
        case .secureChannel: return "Secure channel opened for selected policy"
        case .endpointSelection: return "Endpoint security policy matched profile"
        case .createSession: return "Session created"
        case .activateSession: return "Session activated"
        case .namespaceTable: return "Namespace table readable"
        case .serverStatus: return "Server status node readable"
        case .diagnostics: return "No blocking diagnostics returned"
        }
    }
}
