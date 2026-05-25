import Foundation
import SwiftUI
import Combine

class ConnectionProfileManager: ObservableObject {
    static let shared = ConnectionProfileManager()
    
    @Published var profiles: [ConnectionProfile] = []
    @Published var quickConnectTemplates: [QuickConnectTemplate] = []
    
    private let profilesKey = "connection_profiles"
    private let templatesKey = "quick_connect_templates"
    
    struct ConnectionProfile: Identifiable, Codable {
        var id = UUID()
        var name: String
        var category: OPCUAServer.ProfileCategory
        var server: OPCUAServer
        var icon: String = "server.rack"
        var color: String = "blue"
        var tags: [String] = []
        var lastUsed: Date?
        var useCount: Int = 0
        var isFavorite: Bool = false
        var notes: String = ""
        var autoConnect: Bool = false
        var reconnectOnFailure: Bool = true
        var reconnectInterval: TimeInterval = 5.0
        var maxReconnectAttempts: Int = 3
    }
    
    struct QuickConnectTemplate: Identifiable, Codable {
        var id = UUID()
        var name: String
        var description: String
        var category: TemplateCategory
        var defaultPort: Int
        var defaultSecurityMode: SecurityMode
        var defaultSecurityPolicy: SecurityPolicy
        var defaultAuthMode: AuthenticationMode
        var icon: String
        var recommendedSettings: [String]
        
        enum TemplateCategory: String, CaseIterable, Codable {
            case industrial = "Industrial"
            case simulation = "Simulation"
            case testing = "Testing"
            case cloud = "Cloud"
            case edge = "Edge Device"
            
            var color: Color {
                switch self {
                case .industrial: return .gray
                case .simulation: return .blue
                case .testing: return .orange
                case .cloud: return .purple
                case .edge: return .green
                }
            }
        }
    }
    
    init() {
        loadProfiles()
        loadTemplates()
        
        if quickConnectTemplates.isEmpty {
            createDefaultTemplates()
        }
    }
    
    private func createDefaultTemplates() {
        quickConnectTemplates = [
            QuickConnectTemplate(
                name: "Siemens S7",
                description: "Connect to Siemens S7 PLCs",
                category: .industrial,
                defaultPort: 4840,
                defaultSecurityMode: .signAndEncrypt,
                defaultSecurityPolicy: .basic256Sha256,
                defaultAuthMode: .usernamePassword,
                icon: "cpu",
                recommendedSettings: [
                    "Enable automatic reconnection",
                    "Set monitoring interval to 1000ms",
                    "Use certificate authentication for production"
                ]
            ),
            QuickConnectTemplate(
                name: "KEPServerEX",
                description: "Connect to KEPServerEX OPC UA Server",
                category: .industrial,
                defaultPort: 49320,
                defaultSecurityMode: .signAndEncrypt,
                defaultSecurityPolicy: .basic256Sha256,
                defaultAuthMode: .usernamePassword,
                icon: "server.rack",
                recommendedSettings: [
                    "Configure trust list",
                    "Enable subscription persistence"
                ]
            ),
            QuickConnectTemplate(
                name: "Prosys Simulation",
                description: "Connect to Prosys OPC UA Simulation Server",
                category: .simulation,
                defaultPort: 53530,
                defaultSecurityMode: .none,
                defaultSecurityPolicy: .none,
                defaultAuthMode: .anonymous,
                icon: "play.circle",
                recommendedSettings: [
                    "Perfect for testing and development",
                    "No security required"
                ]
            ),
            QuickConnectTemplate(
                name: "Azure IoT Edge",
                description: "Connect to Azure IoT Edge OPC Publisher",
                category: .cloud,
                defaultPort: 62222,
                defaultSecurityMode: .signAndEncrypt,
                defaultSecurityPolicy: .aes256Sha256RsaPss,
                defaultAuthMode: .certificate,
                icon: "cloud",
                recommendedSettings: [
                    "Use certificate authentication",
                    "Configure message size limits",
                    "Enable cloud telemetry"
                ]
            ),
            QuickConnectTemplate(
                name: "Unified Automation Demo",
                description: "UA Demo Server for testing",
                category: .testing,
                defaultPort: 48030,
                defaultSecurityMode: .signAndEncrypt,
                defaultSecurityPolicy: .basic256Sha256,
                defaultAuthMode: .usernamePassword,
                icon: "hammer",
                recommendedSettings: [
                    "Username: user1",
                    "Password: password"
                ]
            )
        ]
        saveTemplates()
    }
    
    func createProfile(from server: OPCUAServer, name: String? = nil) -> ConnectionProfile {
        let profile = ConnectionProfile(
            name: name ?? server.name,
            category: .development, // Default category
            server: server
        )
        
        profiles.append(profile)
        saveProfiles()
        
        return profile
    }
    
    func updateProfile(_ profile: ConnectionProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            saveProfiles()
        }
    }
    
    func deleteProfile(_ profile: ConnectionProfile) {
        profiles.removeAll { $0.id == profile.id }
        saveProfiles()
    }
    
    func toggleFavorite(for profile: ConnectionProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index].isFavorite.toggle()
            saveProfiles()
        }
    }
    
    func incrementUseCount(for profile: ConnectionProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index].useCount += 1
            profiles[index].lastUsed = Date()
            saveProfiles()
        }
    }
    
    func applyTemplate(_ template: QuickConnectTemplate, to server: inout OPCUAServer) {
        server.port = template.defaultPort
        server.securityMode = template.defaultSecurityMode
        server.securityPolicy = template.defaultSecurityPolicy
        server.authenticationMode = template.defaultAuthMode
    }
    
    func exportProfile(_ profile: ConnectionProfile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(Self.sanitized(profile))
    }

    func importProfile(from data: Data) throws -> ConnectionProfile {
        let decoder = JSONDecoder()
        var profile = try decoder.decode(ConnectionProfile.self, from: data)
        // If the bundle came from an older build that included the password,
        // move it to Keychain and clear the field so the on-disk plist stays
        // clean on the next save.
        let hadInlinePassword = Self.hasInlinePassword(profile)
        let migrated = Self.migrateInlinePasswordToKeychain(in: &profile)
        let securityFilesMigrated = Self.migrateInlineSecurityFilesToKeychain(in: &profile)
        if hadInlinePassword && !migrated {
            throw ConnectionProfileError.keychainMigrationFailed(profile.server.id)
        }
        if securityFilesMigrated == .failed {
            throw ConnectionProfileError.securityFileMigrationFailed(profile.server.id)
        }

        profiles.append(profile)
        saveProfiles()

        return profile
    }

    func exportAllProfiles() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(profiles.map(Self.sanitized))
    }

    func importProfiles(from data: Data, replace: Bool = false) throws {
        let decoder = JSONDecoder()
        var importedProfiles = try decoder.decode([ConnectionProfile].self, from: data)
        for index in importedProfiles.indices {
            let hadInlinePassword = Self.hasInlinePassword(importedProfiles[index])
            let migrated = Self.migrateInlinePasswordToKeychain(in: &importedProfiles[index])
            let securityFilesMigrated = Self.migrateInlineSecurityFilesToKeychain(in: &importedProfiles[index])
            if hadInlinePassword && !migrated {
                throw ConnectionProfileError.keychainMigrationFailed(importedProfiles[index].server.id)
            }
            if securityFilesMigrated == .failed {
                throw ConnectionProfileError.securityFileMigrationFailed(importedProfiles[index].server.id)
            }
        }

        if replace {
            profiles = importedProfiles
        } else {
            profiles.append(contentsOf: importedProfiles)
        }

        saveProfiles()
    }
    
    var favoriteProfiles: [ConnectionProfile] {
        profiles.filter { $0.isFavorite }
    }
    
    var recentProfiles: [ConnectionProfile] {
        profiles
            .filter { $0.lastUsed != nil }
            .sorted { ($0.lastUsed ?? Date.distantPast) > ($1.lastUsed ?? Date.distantPast) }
            .prefix(5)
            .map { $0 }
    }
    
    var mostUsedProfiles: [ConnectionProfile] {
        profiles
            .filter { $0.useCount > 0 }
            .sorted { $0.useCount > $1.useCount }
            .prefix(5)
            .map { $0 }
    }
    
    func profilesByCategory(_ category: OPCUAServer.ProfileCategory) -> [ConnectionProfile] {
        profiles.filter { $0.category == category }
    }
    
    private func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              var decodedProfiles = try? JSONDecoder().decode([ConnectionProfile].self, from: data) else {
            return
        }

        // Migrate any cleartext password from an older build into Keychain,
        // then resave so the plist no longer contains the secret.
        var migrated = false
        var migrationFailed = false
        for index in decodedProfiles.indices {
            if Self.migrateInlinePasswordToKeychain(in: &decodedProfiles[index]) {
                migrated = true
            }
            switch Self.migrateInlineSecurityFilesToKeychain(in: &decodedProfiles[index]) {
            case .migrated:
                migrated = true
            case .failed:
                migrationFailed = true
            case .unchanged:
                break
            }
        }
        profiles = decodedProfiles
        if migrated && !migrationFailed {
            saveProfiles()
        }
    }

    private func saveProfiles() {
        // Strip credentials before writing to UserDefaults. Passwords belong
        // in Keychain only (ServerCredentialStore); UserDefaults persists as
        // cleartext plist on disk.
        let sanitized = profiles.map(Self.sanitized)
        if let encoded = try? JSONEncoder().encode(sanitized) {
            UserDefaults.standard.set(encoded, forKey: profilesKey)
        }
    }

    nonisolated private static func sanitized(_ profile: ConnectionProfile) -> ConnectionProfile {
        var copy = profile
        copy.server.password = nil
        copy.server.certificatePath = nil
        copy.server.privateKeyPath = nil
        copy.server.serverCertificatePath = nil
        return copy
    }

    @discardableResult
    nonisolated private static func migrateInlinePasswordToKeychain(in profile: inout ConnectionProfile) -> Bool {
        guard let password = profile.server.password, !password.isEmpty else {
            profile.server.password = nil
            return false
        }
        if ServerCredentialStore.password(for: profile.server.id) != nil ||
            ServerCredentialStore.savePassword(password, for: profile.server.id) {
            profile.server.password = nil
            return true
        }

        print("Failed to migrate profile password for server \(profile.server.id) into Keychain; leaving profile password intact.")
        return false
    }

    nonisolated private static func hasInlinePassword(_ profile: ConnectionProfile) -> Bool {
        guard let password = profile.server.password else {
            return false
        }
        return !password.isEmpty
    }

    private enum SecurityFileMigrationResult {
        case unchanged
        case migrated
        case failed
    }

    @discardableResult
    nonisolated private static func migrateInlineSecurityFilesToKeychain(in profile: inout ConnectionProfile) -> SecurityFileMigrationResult {
        var result = SecurityFileMigrationResult.unchanged

        if case .failed = mergeSecurityFileMigrationResult(
            &result,
            migrateInlineSecurityFile(path: &profile.server.certificatePath, serverId: profile.server.id, role: .clientCertificate)
        ) {
            return .failed
        }
        if case .failed = mergeSecurityFileMigrationResult(
            &result,
            migrateInlineSecurityFile(path: &profile.server.privateKeyPath, serverId: profile.server.id, role: .privateKey)
        ) {
            return .failed
        }
        if case .failed = mergeSecurityFileMigrationResult(
            &result,
            migrateInlineSecurityFile(path: &profile.server.serverCertificatePath, serverId: profile.server.id, role: .serverCertificate)
        ) {
            return .failed
        }

        return result
    }

    nonisolated private static func mergeSecurityFileMigrationResult(
        _ current: inout SecurityFileMigrationResult,
        _ next: SecurityFileMigrationResult
    ) -> SecurityFileMigrationResult {
        switch next {
        case .failed:
            current = .failed
        case .migrated:
            if case .unchanged = current {
                current = .migrated
            }
        case .unchanged:
            break
        }
        return current
    }

    @discardableResult
    nonisolated private static func migrateInlineSecurityFile(
        path: inout String?,
        serverId: UUID,
        role: ServerSecurityFileRole
    ) -> SecurityFileMigrationResult {
        guard let value = path else {
            return .unchanged
        }

        guard !value.isEmpty else {
            path = nil
            return .migrated
        }

        if ServerSecurityFileStore.path(for: serverId, role: role) != nil ||
            ServerSecurityFileStore.savePath(value, for: serverId, role: role) {
            path = nil
            return .migrated
        }

        print("Failed to migrate profile \(role.rawValue) path for server \(serverId) into Keychain; leaving profile path intact.")
        return .failed
    }

    private enum ConnectionProfileError: LocalizedError {
        case keychainMigrationFailed(UUID)
        case securityFileMigrationFailed(UUID)

        var errorDescription: String? {
            switch self {
            case .keychainMigrationFailed(let serverId):
                return "Could not save imported password to Keychain for server \(serverId)."
            case .securityFileMigrationFailed(let serverId):
                return "Could not save imported certificate or key path to Keychain for server \(serverId)."
            }
        }
    }
    
    private func loadTemplates() {
        if let data = UserDefaults.standard.data(forKey: templatesKey),
           let decodedTemplates = try? JSONDecoder().decode([QuickConnectTemplate].self, from: data) {
            quickConnectTemplates = decodedTemplates
        }
    }
    
    private func saveTemplates() {
        if let encoded = try? JSONEncoder().encode(quickConnectTemplates) {
            UserDefaults.standard.set(encoded, forKey: templatesKey)
        }
    }
}
