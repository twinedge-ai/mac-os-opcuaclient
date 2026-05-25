import Foundation
import SwiftUI
import Combine

enum ConnectionStatus: String, CaseIterable, Codable {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case connected = "Connected"
    case error = "Error"

    var color: Color {
        switch self {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }

    var systemImage: String {
        switch self {
        case .disconnected: return "circle.fill"
        case .connecting: return "circle.dotted"
        case .connected: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }
}

enum ConnectionQuality: String, CaseIterable, Codable {
    case excellent = "Excellent"
    case good = "Good"
    case poor = "Poor"
    case unknown = "Unknown"

    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .orange
        case .poor: return .red
        case .unknown: return .gray
        }
    }

    var systemImage: String {
        switch self {
        case .excellent: return "wifi"
        case .good: return "wifi.exclamationmark"
        case .poor: return "wifi.slash"
        case .unknown: return "questionmark"
        }
    }
}

enum SecurityMode: String, CaseIterable, Identifiable, Codable {
    case none = "None"
    case sign = "Sign"
    case signAndEncrypt = "Sign & Encrypt"

    var id: String { self.rawValue }
}

enum SecurityPolicy: String, CaseIterable, Identifiable, Codable {
    case none = "None"
    case basic128Rsa15 = "Basic128Rsa15"
    case basic256 = "Basic256"
    case basic256Sha256 = "Basic256Sha256"
    case aes128Sha256RsaOaep = "Aes128_Sha256_RsaOaep"
    case aes256Sha256RsaPss = "Aes256_Sha256_RsaPss"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .basic128Rsa15: return "Basic128Rsa15 (Deprecated)"
        case .basic256: return "Basic256 (Deprecated)"
        case .basic256Sha256: return "Basic256Sha256"
        case .aes128Sha256RsaOaep: return "Aes128-Sha256-RsaOaep"
        case .aes256Sha256RsaPss: return "Aes256-Sha256-RsaPss (Recommended)"
        }
    }
    
    var securityLevel: Int {
        switch self {
        case .none: return 0
        case .basic128Rsa15: return 1
        case .basic256: return 2
        case .basic256Sha256: return 3
        case .aes128Sha256RsaOaep: return 4
        case .aes256Sha256RsaPss: return 5
        }
    }
    
    var isDeprecated: Bool {
        switch self {
        case .basic128Rsa15, .basic256: return true
        default: return false
        }
    }
}

enum AuthenticationMode: String, CaseIterable, Identifiable, Codable {
    case anonymous = "Anonymous"
    case usernamePassword = "Username/Password"
    case certificate = "Certificate"

    var id: String { self.rawValue }
}

enum NetworkSchema: String, CaseIterable, Identifiable, Codable {
    case opcTcp = "opc.tcp"
    case opcWss = "opc.wss"

    static var allCases: [NetworkSchema] { [.opcTcp] }

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .opcTcp: return "OPC TCP"
        case .opcWss: return "OPC WebSocket (WSS)"
        }
    }

    var prefix: String {
        return self.rawValue + "://"
    }

    var defaultPort: Int {
        switch self {
        case .opcTcp: return 4840
        case .opcWss: return 443
        }
    }
}

enum ProfileTrustBehavior: String, CaseIterable, Identifiable, Codable {
    case blockUnknown = "Block Unknown Certificates"
    case temporaryTrust = "Trust Temporarily"
    case manualReview = "Manual Review"

    static var allCases: [ProfileTrustBehavior] {
        [.blockUnknown]
    }

    var id: String { rawValue }
}

enum KeepalivePolicy: String, CaseIterable, Identifiable, Codable {
    case standard = "Standard"
    case aggressive = "Aggressive"
    case conservative = "Conservative"

    var id: String { rawValue }
}

enum ReconnectPolicy: String, CaseIterable, Identifiable, Codable {
    case manual = "Manual"
    case automatic = "Automatic"
    case automaticWithBackoff = "Automatic with Backoff"

    var id: String { rawValue }
}

struct OPCUAServer: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var networkSchema: NetworkSchema
    var host: String
    var port: Int
    var securityMode: SecurityMode
    var securityPolicy: SecurityPolicy = .none
    var authenticationMode: AuthenticationMode
    var username: String?
    var password: String?
    var certificatePath: String?
    var privateKeyPath: String?
    var serverCertificatePath: String?
    var profileName: String?
    var profileCategory: ProfileCategory = .development
    var status: ConnectionStatus = .disconnected
    var lastConnected: Date?
    var description: String = ""
    var isDefault: Bool = false
    var applicationURI: String = ClientApplicationURI.installDefault
    var requestedTimeout: Double = 10
    var sessionTimeout: Double = 60
    var localeIDs: [String] = []
    var keepalivePolicy: KeepalivePolicy = .standard
    var reconnectPolicy: ReconnectPolicy = .automaticWithBackoff
    var trustBehavior: ProfileTrustBehavior = .blockUnknown
    var tags: [String] = []
    var notes: String = ""

    /// Computed property to get the full endpoint URL
    var endpoint: String {
        return "\(networkSchema.prefix)\(host):\(port)"
    }

    init(
        id: UUID = UUID(),
        name: String,
        networkSchema: NetworkSchema = .opcTcp,
        host: String,
        port: Int = 4840,
        securityMode: SecurityMode,
        securityPolicy: SecurityPolicy = .none,
        authenticationMode: AuthenticationMode,
        username: String? = nil,
        password: String? = nil,
        certificatePath: String? = nil,
        privateKeyPath: String? = nil,
        serverCertificatePath: String? = nil,
        status: ConnectionStatus = .disconnected,
        lastConnected: Date? = nil,
        description: String = "",
        profileName: String? = nil,
        profileCategory: ProfileCategory = .development,
        isDefault: Bool = false,
        applicationURI: String = ClientApplicationURI.installDefault,
        requestedTimeout: Double = 10,
        sessionTimeout: Double = 60,
        localeIDs: [String] = [],
        keepalivePolicy: KeepalivePolicy = .standard,
        reconnectPolicy: ReconnectPolicy = .automaticWithBackoff,
        trustBehavior: ProfileTrustBehavior = .blockUnknown,
        tags: [String] = [],
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.networkSchema = networkSchema
        self.host = host
        self.port = port
        self.securityMode = securityMode
        self.securityPolicy = securityPolicy
        self.authenticationMode = authenticationMode
        self.username = username
        self.password = password
        self.certificatePath = certificatePath
        self.privateKeyPath = privateKeyPath
        self.serverCertificatePath = serverCertificatePath
        self.status = status
        self.lastConnected = lastConnected
        self.description = description
        self.profileName = profileName
        self.profileCategory = profileCategory
        self.isDefault = isDefault
        self.applicationURI = applicationURI
        self.requestedTimeout = requestedTimeout
        self.sessionTimeout = sessionTimeout
        self.localeIDs = localeIDs
        self.keepalivePolicy = keepalivePolicy
        self.reconnectPolicy = reconnectPolicy
        self.trustBehavior = trustBehavior
        self.tags = tags
        self.notes = notes
    }

    // Legacy initializer for backward compatibility (parses endpoint string)
    init(
        id: UUID = UUID(),
        name: String,
        endpoint: String,
        port: Int,
        securityMode: SecurityMode,
        authenticationMode: AuthenticationMode,
        username: String? = nil,
        password: String? = nil,
        status: ConnectionStatus = .disconnected,
        lastConnected: Date? = nil,
        description: String = ""
    ) {
        self.id = id
        self.name = name

        // Parse the endpoint to extract schema and host
        if endpoint.hasPrefix("opc.wss://") {
            self.networkSchema = .opcWss
            self.host = String(endpoint.dropFirst("opc.wss://".count))
        } else if endpoint.hasPrefix("opc.tcp://") {
            self.networkSchema = .opcTcp
            self.host = String(endpoint.dropFirst("opc.tcp://".count))
        } else {
            self.networkSchema = .opcTcp
            self.host = endpoint
        }

        // Remove port from host if present
        if let colonIndex = self.host.lastIndex(of: ":") {
            self.host = String(self.host[..<colonIndex])
        }

        self.port = port
        self.securityMode = securityMode
        self.securityPolicy = .none
        self.authenticationMode = authenticationMode
        self.username = username
        self.password = password
        self.certificatePath = nil
        self.privateKeyPath = nil
        self.serverCertificatePath = nil
        self.status = status
        self.lastConnected = lastConnected
        self.description = description
        self.profileName = nil
        self.profileCategory = .development
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case networkSchema
        case host
        case port
        case securityMode
        case securityPolicy
        case authenticationMode
        case username
        case password
        case certificatePath
        case privateKeyPath
        case serverCertificatePath
        case profileName
        case profileCategory
        case status
        case lastConnected
        case description
        case isDefault
        case applicationURI
        case requestedTimeout
        case sessionTimeout
        case localeIDs
        case keepalivePolicy
        case reconnectPolicy
        case trustBehavior
        case tags
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        networkSchema = try container.decodeIfPresent(NetworkSchema.self, forKey: .networkSchema) ?? .opcTcp
        host = try container.decode(String.self, forKey: .host)
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? networkSchema.defaultPort
        securityMode = try container.decodeIfPresent(SecurityMode.self, forKey: .securityMode) ?? .none
        securityPolicy = try container.decodeIfPresent(SecurityPolicy.self, forKey: .securityPolicy) ?? .none
        authenticationMode = try container.decodeIfPresent(AuthenticationMode.self, forKey: .authenticationMode) ?? .anonymous
        username = try container.decodeIfPresent(String.self, forKey: .username)
        password = try container.decodeIfPresent(String.self, forKey: .password)
        certificatePath = try container.decodeIfPresent(String.self, forKey: .certificatePath)
        privateKeyPath = try container.decodeIfPresent(String.self, forKey: .privateKeyPath)
        serverCertificatePath = try container.decodeIfPresent(String.self, forKey: .serverCertificatePath)
        profileName = try container.decodeIfPresent(String.self, forKey: .profileName)
        profileCategory = try container.decodeIfPresent(ProfileCategory.self, forKey: .profileCategory) ?? .development
        status = try container.decodeIfPresent(ConnectionStatus.self, forKey: .status) ?? .disconnected
        lastConnected = try container.decodeIfPresent(Date.self, forKey: .lastConnected)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        applicationURI = try container.decodeIfPresent(String.self, forKey: .applicationURI) ?? ClientApplicationURI.installDefault
        requestedTimeout = try container.decodeIfPresent(Double.self, forKey: .requestedTimeout) ?? 10
        sessionTimeout = try container.decodeIfPresent(Double.self, forKey: .sessionTimeout) ?? 60
        localeIDs = try container.decodeIfPresent([String].self, forKey: .localeIDs) ?? []
        keepalivePolicy = try container.decodeIfPresent(KeepalivePolicy.self, forKey: .keepalivePolicy) ?? .standard
        reconnectPolicy = try container.decodeIfPresent(ReconnectPolicy.self, forKey: .reconnectPolicy) ?? .automaticWithBackoff
        trustBehavior = try container.decodeIfPresent(ProfileTrustBehavior.self, forKey: .trustBehavior) ?? .blockUnknown
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(networkSchema, forKey: .networkSchema)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(securityMode, forKey: .securityMode)
        try container.encode(securityPolicy, forKey: .securityPolicy)
        try container.encode(authenticationMode, forKey: .authenticationMode)
        try container.encodeIfPresent(username, forKey: .username)
        // Passwords and local certificate/private-key paths are intentionally
        // omitted from Codable output. They are device-local sensitive
        // references stored via Keychain-backed helpers.
        try container.encodeIfPresent(profileName, forKey: .profileName)
        try container.encode(profileCategory, forKey: .profileCategory)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(lastConnected, forKey: .lastConnected)
        try container.encode(description, forKey: .description)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(applicationURI, forKey: .applicationURI)
        try container.encode(requestedTimeout, forKey: .requestedTimeout)
        try container.encode(sessionTimeout, forKey: .sessionTimeout)
        try container.encode(localeIDs, forKey: .localeIDs)
        try container.encode(keepalivePolicy, forKey: .keepalivePolicy)
        try container.encode(reconnectPolicy, forKey: .reconnectPolicy)
        try container.encode(trustBehavior, forKey: .trustBehavior)
        try container.encode(tags, forKey: .tags)
        try container.encode(notes, forKey: .notes)
    }
    
    enum ProfileCategory: String, CaseIterable, Codable {
        case development = "Development"
        case testing = "Testing"
        case production = "Production"
        case custom = "Custom"
        
        var color: Color {
            switch self {
            case .development: return .blue
            case .testing: return .orange
            case .production: return .red
            case .custom: return .purple
            }
        }
    }
}

class NodeInfo: Identifiable, ObservableObject, Hashable {
    let id = UUID()
    let nodeId: String
    let displayName: String
    let nodeClass: NodeClass
    let dataType: String?
    @Published var value: String?
    @Published var timestamp: Date?
    @Published var quality: Quality
    
    @Published var children: [NodeInfo]?
    @Published var isExpanded: Bool = false
    @Published var hasChildren: Bool = true
    @Published var isLoading: Bool = false
    
    init(
        nodeId: String,
        displayName: String,
        nodeClass: NodeClass,
        dataType: String? = nil,
        value: String? = nil,
        timestamp: Date? = nil,
        quality: Quality = .good,
        children: [NodeInfo]? = nil,
        isExpanded: Bool = false
    ) {
        self.nodeId = nodeId
        self.displayName = displayName
        self.nodeClass = nodeClass
        self.dataType = dataType
        self.value = value
        self.timestamp = timestamp
        self.quality = quality
        self.children = children
        self.isExpanded = isExpanded
        
        // If we have children, we definitely have children.
        // If children is nil, we assume we MIGHT have children until we check,
        // unless it's a Variable/Method which usually are leaves in this context
        // (though they can have properties).
        if let children = children, !children.isEmpty {
            self.hasChildren = true
        } else if nodeClass == .variable || nodeClass == .method {
            // Usually treat as leaves for simple browsing, or set false
            self.hasChildren = false 
        } else {
            self.hasChildren = true
        }
    }
    
    static func == (lhs: NodeInfo, rhs: NodeInfo) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    enum NodeClass: String, CaseIterable {
        case object = "Object"
        case variable = "Variable"
        case method = "Method"
        case objectType = "ObjectType"
        case variableType = "VariableType"
        case referenceType = "ReferenceType"
        case dataType = "DataType"
        case view = "View"
        
        var systemImage: String {
            switch self {
            case .object: return "folder.fill"
            case .variable: return "tag.fill"
            case .method: return "function"
            case .objectType: return "cube.fill"
            case .variableType: return "tag"
            case .referenceType: return "link"
            case .dataType: return "doc.text.fill"
            case .view: return "eye.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .object: return .blue
            case .variable: return .green
            case .method: return .purple
            case .objectType: return .orange
            case .variableType: return .mint
            case .referenceType: return .indigo
            case .dataType: return .brown
            case .view: return .cyan
            }
        }
    }
    
    enum Quality: String {
        case good = "Good"
        case bad = "Bad"
        case uncertain = "Uncertain"
        
        var color: Color {
            switch self {
            case .good: return .green
            case .bad: return .red
            case .uncertain: return .orange
            }
        }
    }
}

enum SamplingPreset: String, CaseIterable, Identifiable, Codable {
    case realtime = "Real-time"
    case fast = "Fast"
    case standard = "Standard"
    case slow = "Slow"
    case custom = "Custom"

    var id: String { rawValue }

    var interval: Double {
        switch self {
        case .realtime: return 100
        case .fast: return 250
        case .standard: return 1000
        case .slow: return 5000
        case .custom: return 1000
        }
    }
}

enum DeadbandType: String, CaseIterable, Identifiable, Codable {
    case none = "None"
    case absolute = "Absolute"
    case percent = "Percent"

    var id: String { rawValue }
}

struct Subscription: Identifiable, Hashable {
    var id: UUID
    var name: String
    var serverId: UUID
    var publishingInterval: Double
    var priority: Int
    var isActive: Bool
    var monitoredItems: [MonitoredItem]

    init(
        id: UUID = UUID(),
        name: String,
        serverId: UUID,
        publishingInterval: Double,
        priority: Int,
        isActive: Bool,
        monitoredItems: [MonitoredItem]
    ) {
        self.id = id
        self.name = name
        self.serverId = serverId
        self.publishingInterval = publishingInterval
        self.priority = priority
        self.isActive = isActive
        self.monitoredItems = monitoredItems
    }
}

struct MonitoredItem: Identifiable, Hashable {
    var id: UUID
    var nodeId: String
    var displayName: String
    var samplingInterval: Double
    var samplingPreset: SamplingPreset
    var deadbandType: DeadbandType
    var deadbandValue: Double
    var queueSize: Int
    var discardOldest: Bool
    var currentValue: String?
    var timestamp: Date?
    var quality: NodeInfo.Quality

    init(
        id: UUID = UUID(),
        nodeId: String,
        displayName: String,
        samplingInterval: Double,
        samplingPreset: SamplingPreset = .standard,
        deadbandType: DeadbandType = .none,
        deadbandValue: Double = 0,
        queueSize: Int,
        discardOldest: Bool,
        currentValue: String?,
        timestamp: Date?,
        quality: NodeInfo.Quality
    ) {
        self.id = id
        self.nodeId = nodeId
        self.displayName = displayName
        self.samplingInterval = samplingInterval
        self.samplingPreset = samplingPreset
        self.deadbandType = deadbandType
        self.deadbandValue = deadbandValue
        self.queueSize = queueSize
        self.discardOldest = discardOldest
        self.currentValue = currentValue
        self.timestamp = timestamp
        self.quality = quality
    }
}

struct DataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
    let quality: NodeInfo.Quality
    
    // Initialize with current timestamp if not provided
    init(timestamp: Date = Date(), value: Double, quality: NodeInfo.Quality = .good) {
        self.timestamp = timestamp
        self.value = value
        self.quality = quality
    }
}
