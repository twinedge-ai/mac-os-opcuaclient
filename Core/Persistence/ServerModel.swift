import Foundation
import SwiftData

@Model
final class ServerModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var networkSchema: String
    var host: String
    var port: Int
    var securityMode: String
    var securityPolicy: String
    var authenticationMode: String
    // Legacy migration field. New values are stored in Keychain via
    // ServerCredentialStore and this property is cleared before saving.
    var username: String?
    var password: String?
    var certificatePath: String?
    var privateKeyPath: String?
    var serverCertificatePath: String?
    var serverDescription: String
    var lastConnected: Date?
    var createdAt: Date
    var updatedAt: Date
    var isDefault: Bool = false
    var applicationURI: String
    var requestedTimeout: Double
    var sessionTimeout: Double
    var localeIDsCSV: String
    var keepalivePolicy: String
    var reconnectPolicy: String
    var trustBehavior: String
    var tagsCSV: String
    var notes: String
    
    // Relationship to subscriptions
    @Relationship(deleteRule: .cascade, inverse: \SubscriptionModel.server)
    var subscriptions: [SubscriptionModel]

    init(
        id: UUID = UUID(),
        name: String,
        networkSchema: String = "opc.tcp",
        host: String,
        port: Int = 4840,
        securityMode: String = "None",
        securityPolicy: String = "None",
        authenticationMode: String = "Anonymous",
        username: String? = nil,
        password: String? = nil,
        certificatePath: String? = nil,
        privateKeyPath: String? = nil,
        serverCertificatePath: String? = nil,
        serverDescription: String = "",
        lastConnected: Date? = nil,
        isDefault: Bool = false,
        applicationURI: String = ClientApplicationURI.installDefault,
        requestedTimeout: Double = 10,
        sessionTimeout: Double = 60,
        localeIDsCSV: String = "",
        keepalivePolicy: String = KeepalivePolicy.standard.rawValue,
        reconnectPolicy: String = ReconnectPolicy.automaticWithBackoff.rawValue,
        trustBehavior: String = ProfileTrustBehavior.blockUnknown.rawValue,
        tagsCSV: String = "",
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
        // AppState persists credentials and security file bookmarks to Keychain
        // before creating the model.
        self.password = nil
        self.certificatePath = nil
        self.privateKeyPath = nil
        self.serverCertificatePath = nil
        self.serverDescription = serverDescription
        self.lastConnected = lastConnected
        self.isDefault = isDefault
        self.applicationURI = applicationURI
        self.requestedTimeout = requestedTimeout
        self.sessionTimeout = sessionTimeout
        self.localeIDsCSV = localeIDsCSV
        self.keepalivePolicy = keepalivePolicy
        self.reconnectPolicy = reconnectPolicy
        self.trustBehavior = trustBehavior
        self.tagsCSV = tagsCSV
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
        self.subscriptions = []
    }

    /// Convert to OPCUAServer struct for use with existing code
    func toOPCUAServer() -> OPCUAServer {
        OPCUAServer(
            id: id,
            name: name,
            networkSchema: NetworkSchema(rawValue: networkSchema) ?? .opcTcp,
            host: host,
            port: port,
            securityMode: SecurityMode(rawValue: securityMode) ?? .none,
            securityPolicy: SecurityPolicy(rawValue: securityPolicy) ?? .none,
            authenticationMode: AuthenticationMode(rawValue: authenticationMode) ?? .anonymous,
            username: username,
            password: ServerCredentialStore.password(for: id) ?? password,
            certificatePath: ServerSecurityFileStore.path(for: id, role: .clientCertificate) ?? certificatePath,
            privateKeyPath: ServerSecurityFileStore.path(for: id, role: .privateKey) ?? privateKeyPath,
            serverCertificatePath: ServerSecurityFileStore.path(for: id, role: .serverCertificate) ?? serverCertificatePath,
            status: .disconnected,
            lastConnected: lastConnected,
            description: serverDescription,
            isDefault: isDefault,
            applicationURI: applicationURI,
            requestedTimeout: requestedTimeout,
            sessionTimeout: sessionTimeout,
            localeIDs: Self.decodeCSV(localeIDsCSV),
            keepalivePolicy: KeepalivePolicy(rawValue: keepalivePolicy) ?? .standard,
            reconnectPolicy: ReconnectPolicy(rawValue: reconnectPolicy) ?? .automaticWithBackoff,
            trustBehavior: ProfileTrustBehavior(rawValue: trustBehavior) ?? .blockUnknown,
            tags: Self.decodeCSV(tagsCSV),
            notes: notes
        )
    }

    /// Update from OPCUAServer struct
    func update(from server: OPCUAServer) {
        self.name = server.name
        self.networkSchema = server.networkSchema.rawValue
        self.host = server.host
        self.port = server.port
        self.securityMode = server.securityMode.rawValue
        self.securityPolicy = server.securityPolicy.rawValue
        self.authenticationMode = server.authenticationMode.rawValue
        self.username = server.username
        // AppState persists credentials and security file bookmarks to Keychain
        // before updating the model.
        self.password = nil
        self.certificatePath = nil
        self.privateKeyPath = nil
        self.serverCertificatePath = nil
        self.serverDescription = server.description
        self.lastConnected = server.lastConnected
        self.isDefault = server.isDefault
        self.applicationURI = server.applicationURI
        self.requestedTimeout = server.requestedTimeout
        self.sessionTimeout = server.sessionTimeout
        self.localeIDsCSV = Self.encodeCSV(server.localeIDs)
        self.keepalivePolicy = server.keepalivePolicy.rawValue
        self.reconnectPolicy = server.reconnectPolicy.rawValue
        self.trustBehavior = server.trustBehavior.rawValue
        self.tagsCSV = Self.encodeCSV(server.tags)
        self.notes = server.notes
        self.updatedAt = Date()
    }

    /// Create ServerModel from OPCUAServer struct
    static func from(_ server: OPCUAServer) -> ServerModel {
        ServerModel(
            id: server.id,
            name: server.name,
            networkSchema: server.networkSchema.rawValue,
            host: server.host,
            port: server.port,
            securityMode: server.securityMode.rawValue,
            securityPolicy: server.securityPolicy.rawValue,
            authenticationMode: server.authenticationMode.rawValue,
            username: server.username,
            password: nil,
            certificatePath: nil,
            privateKeyPath: nil,
            serverCertificatePath: nil,
            serverDescription: server.description,
            lastConnected: server.lastConnected,
            isDefault: server.isDefault,
            applicationURI: server.applicationURI,
            requestedTimeout: server.requestedTimeout,
            sessionTimeout: server.sessionTimeout,
            localeIDsCSV: encodeCSV(server.localeIDs),
            keepalivePolicy: server.keepalivePolicy.rawValue,
            reconnectPolicy: server.reconnectPolicy.rawValue,
            trustBehavior: server.trustBehavior.rawValue,
            tagsCSV: encodeCSV(server.tags),
            notes: server.notes
        )
    }

    @discardableResult
    func migrateLegacyPasswordToKeychainIfNeeded() -> Bool {
        guard let password, !password.isEmpty else {
            if self.password != nil {
                self.password = nil
                return true
            }
            return false
        }

        if ServerCredentialStore.password(for: id) != nil ||
            ServerCredentialStore.savePassword(password, for: id) {
            self.password = nil
            return true
        }

        print("Failed to migrate legacy password for server \(id) into Keychain; leaving legacy field intact.")
        return false
    }

    @discardableResult
    func migrateLegacySecurityFilesToKeychainIfNeeded() -> Bool {
        var changed = false

        if migrateLegacySecurityFile(path: certificatePath, role: .clientCertificate) {
            certificatePath = nil
            changed = true
        }

        if migrateLegacySecurityFile(path: privateKeyPath, role: .privateKey) {
            privateKeyPath = nil
            changed = true
        }

        if migrateLegacySecurityFile(path: serverCertificatePath, role: .serverCertificate) {
            serverCertificatePath = nil
            changed = true
        }

        return changed
    }

    private func migrateLegacySecurityFile(path: String?, role: ServerSecurityFileRole) -> Bool {
        guard let path, !path.isEmpty else {
            return path != nil
        }

        if ServerSecurityFileStore.path(for: id, role: role) != nil ||
            ServerSecurityFileStore.savePath(path, for: id, role: role) {
            return true
        }

        print("Failed to migrate legacy \(role.rawValue) path for server \(id) into Keychain; leaving legacy field intact.")
        return false
    }

    private static func encodeCSV(_ values: [String]) -> String {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
    }

    private static func decodeCSV(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
