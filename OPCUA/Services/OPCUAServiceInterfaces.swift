import Foundation

protocol OPCUAConnectionService {
    func connect(_ profile: OPCUAServer) async -> OPCUAServiceResult<OPCUASessionSummary>
    func disconnect(_ profile: OPCUAServer) async
    func connectionStatus(for profile: OPCUAServer) async -> ConnectionStatus
}

protocol OPCUADiscoveryService {
    func discoverEndpoints(endpointURL: String) async -> OPCUAServiceResult<[OPCUAEndpointSummary]>
}

protocol OPCUABrowseService {
    func browseChildren(server: OPCUAServer, nodeId: String) async -> OPCUAServiceResult<[OPCUANodeSummary]>
}

protocol OPCUAReadWriteService {
    func read(server: OPCUAServer, nodeId: String) async -> OPCUAServiceResult<OPCUAReadResult>
    func write(server: OPCUAServer, nodeId: String, value: OPCUAVariantValue) async -> OPCUAServiceResult<OPCUAWriteResult>
}

protocol OPCUASubscriptionService {
    func restoreSubscriptions(for server: OPCUAServer, subscriptions: [Subscription]) async -> OPCUAServiceResult<[OPCUASubscriptionRuntimeSummary]>
}

struct OPCUAServiceResult<Value> {
    let value: Value?
    let status: OPCUAStatusCode
    let diagnostics: [String]
    let startedAt: Date
    let completedAt: Date

    var isGood: Bool {
        status.severity == .good
    }

    static func good(_ value: Value, diagnostics: [String] = []) -> OPCUAServiceResult<Value> {
        let now = Date()
        return OPCUAServiceResult(value: value, status: .good, diagnostics: diagnostics, startedAt: now, completedAt: now)
    }

    static func failure(status: OPCUAStatusCode, diagnostics: [String]) -> OPCUAServiceResult<Value> {
        let now = Date()
        return OPCUAServiceResult(value: nil, status: status, diagnostics: diagnostics, startedAt: now, completedAt: now)
    }
}

struct OPCUASessionSummary: Hashable {
    var endpointURL: String
    var securityMode: SecurityMode
    var securityPolicy: SecurityPolicy
    var namespaceCount: Int
    var serverStatus: String
}

struct OPCUAEndpointSummary: Identifiable, Hashable {
    var id = UUID()
    var endpointURL: String
    var securityMode: SecurityMode
    var securityPolicy: SecurityPolicy
    var userTokenPolicies: [AuthenticationMode]
    var securityLevel: Int
}

struct OPCUANodeSummary: Identifiable, Hashable {
    var id: String { nodeId }
    var nodeId: String
    var displayName: String
    var browseName: String
    var nodeClass: String
    var dataType: String?
    var accessLevel: String?
}

struct OPCUAReadResult: Hashable {
    var nodeId: String
    var value: OPCUAVariantValue
    var sourceTimestamp: Date?
    var serverTimestamp: Date?
    var status: OPCUAStatusCode
}

struct OPCUAWriteResult: Hashable {
    var nodeId: String
    var previousValue: OPCUAVariantValue?
    var writtenValue: OPCUAVariantValue
    var serverTimestamp: Date?
    var status: OPCUAStatusCode
}

struct OPCUASubscriptionRuntimeSummary: Hashable {
    var requestedPublishingInterval: Double
    var revisedPublishingInterval: Double
    var monitoredItemCount: Int
    var status: OPCUAStatusCode
}

indirect enum OPCUAVariantValue: Hashable, Codable {
    case boolean(Bool)
    case double(Double)
    case int(Int)
    case string(String)
    case date(Date)
    case byteString(Data)
    case array([OPCUAVariantValue])

    var displayValue: String {
        switch self {
        case .boolean(let value): return value ? "true" : "false"
        case .double(let value): return String(value)
        case .int(let value): return String(value)
        case .string(let value): return value
        case .date(let value): return ISO8601DateFormatter().string(from: value)
        case .byteString(let value): return value.map { String(format: "%02X", $0) }.joined(separator: " ")
        case .array(let values): return "[" + values.map(\.displayValue).joined(separator: ", ") + "]"
        }
    }
}
