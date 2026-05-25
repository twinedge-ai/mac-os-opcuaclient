import SwiftUI
import SwiftData
import Combine

class AppState: ObservableObject {
    @Published var servers: [OPCUAServer] = []
    @Published var selectedServer: OPCUAServer?
    @Published var showingServerConnection = false
    @Published var subscriptions: [Subscription] = []
    @Published var selectedTab: MainTab = .servers
    @Published var isConnecting = false
    @Published var connectingServerName: String?
    @Published var lastSubscriptionValidationIssues: [MonitoredItemValidation] = []
    @Published var showingDatabaseManagement = false
    @Published var isPersistenceLoaded = false
    @Published var connectionStateRevision = 0
    let writeHistory = WriteHistoryManager()

    // OPC UA Integration
    let connectionManager = OPCUAConnectionManager()
    
    // Persistence manager for subscriptions
    private var subscriptionPersistence: SubscriptionPersistenceManager?
    private let serverDefaultsKey = "opcua.client.servers.fallback"

    // SwiftData model context
    internal var modelContext: ModelContext?

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        
        // Set up bidirectional reference
        connectionManager.appState = self
        
        // Initialize subscription persistence if context is available
        if let context = modelContext {
            self.subscriptionPersistence = SubscriptionPersistenceManager(modelContext: context)
        }
    }

    @MainActor
    func loadInitialDataIfNeeded() async {
        guard !isPersistenceLoaded else {
            return
        }

        await Task.yield()
        loadServers()
        loadSubscriptions()
        isPersistenceLoaded = true
    }

    @MainActor
    func beginConnectionProgress(serverName: String) {
        isConnecting = true
        connectingServerName = serverName
    }

    @MainActor
    func endConnectionProgress() {
        isConnecting = false
        connectingServerName = nil
    }

    @MainActor
    func notifyConnectionStateChanged() {
        connectionStateRevision += 1
    }

    // MARK: - SwiftData Persistence

    /// Load servers from SwiftData
    func loadServers() {
        guard let context = modelContext else {
            print("❌ No model context available for loadServers")
            servers = loadServersFromDefaults()
            selectDefaultServerIfNeeded()
            return
        }

        print("🔍 Loading servers from SwiftData...")

        do {
            let descriptor = FetchDescriptor<ServerModel>(
                sortBy: [SortDescriptor(\.name)]
            )
            let serverModels = try context.fetch(descriptor)
            var migratedLegacySensitiveData = false
            for serverModel in serverModels {
                if serverModel.migrateLegacyPasswordToKeychainIfNeeded() {
                    migratedLegacySensitiveData = true
                }
                if serverModel.migrateLegacySecurityFilesToKeychainIfNeeded() {
                    migratedLegacySensitiveData = true
                }
            }
            if migratedLegacySensitiveData {
                try context.save()
            }
            servers = serverModels.map { $0.toOPCUAServer() }
            if servers.isEmpty {
                servers = loadServersFromDefaults()
            }
            print("📂 Loaded \(servers.count) servers from SwiftData")
            
            if !servers.isEmpty {
                for server in servers {
                    print("  - \(server.name) (ID: \(server.id), Default: \(server.isDefault))")
                }
            }
            
            // Auto-select default server if no server is currently selected
            selectDefaultServerIfNeeded()
        } catch {
            print("❌ Failed to load servers: \(error)")
            print("   Error details: \(String(describing: error))")
            servers = loadServersFromDefaults()
            selectDefaultServerIfNeeded()
        }
    }

    /// Auto-select default server if no server is currently selected
    private func selectDefaultServerIfNeeded() {
        // If no server is selected, try to select the default one
        if selectedServer == nil {
            if let defaultServer = servers.first(where: { $0.isDefault }) {
                selectedServer = defaultServer
                print("🎯 Auto-selected default server: \(defaultServer.name)")
            } else if let firstServer = servers.first {
                // If no default server exists, make the first server default and select it
                setServerAsDefault(firstServer)
                print("🎯 Made first server default and selected: \(firstServer.name)")
            }
        }
    }
    
    /// Set a server as the default server (clears other defaults)
    func setServerAsDefault(_ server: OPCUAServer) {
        // Clear existing defaults
        for i in servers.indices {
            servers[i].isDefault = false
        }
        
        // Set new default
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index].isDefault = true
            selectedServer = servers[index]
            
            // Save the updated server
            saveServer(servers[index])
            
            // Update all other servers to clear their default flag
            for otherServer in servers where otherServer.id != server.id {
                if otherServer.isDefault {
                    var updatedServer = otherServer
                    updatedServer.isDefault = false
                    saveServer(updatedServer)
                }
            }
        }
    }

    /// Save/update a server to SwiftData
    func saveServer(_ server: OPCUAServer, preserveExistingSensitiveReferences: Bool = false) {
        guard let context = modelContext else {
            print("❌ No model context available for saveServer")
            return
        }

        guard persistCredentialChange(for: server, preserveExisting: preserveExistingSensitiveReferences),
              persistSecurityFileChanges(for: server, preserveExisting: preserveExistingSensitiveReferences) else {
            print("❌ Failed to save sensitive server references for: \(server.name)")
            return
        }

        var serverToPersist = server
        serverToPersist.password = nil
        serverToPersist.certificatePath = nil
        serverToPersist.privateKeyPath = nil
        serverToPersist.serverCertificatePath = nil

        print("🔍 Attempting to save server: \(serverToPersist.name) with ID: \(serverToPersist.id)")

        do {
            // Check if server already exists
            let id = serverToPersist.id
            var descriptor = FetchDescriptor<ServerModel>(
                predicate: #Predicate { $0.id == id }
            )
            descriptor.fetchLimit = 1

            let existingServers = try context.fetch(descriptor)
            print("🔍 Found \(existingServers.count) existing server(s) with this ID")

            if let existingModel = existingServers.first {
                // Update existing server
                existingModel.update(from: serverToPersist)
                print("💾 Updated server: \(serverToPersist.name)")
            } else {
                // Insert new server
                let newModel = ServerModel.from(serverToPersist)
                context.insert(newModel)
                print("💾 Inserted new server: \(serverToPersist.name)")
            }

            try context.save()
            print("✅ Successfully saved to SwiftData")
            saveServersToDefaults(servers.replacing(serverToPersist))

            // Reload servers to update the published array
            loadServers()
        } catch {
            print("❌ Failed to save server: \(error)")
            saveServersToDefaults(servers.replacing(serverToPersist))
        }
    }

    private func persistCredentialChange(for server: OPCUAServer, preserveExisting: Bool) -> Bool {
        if let password = server.password, !password.isEmpty {
            return ServerCredentialStore.savePassword(password, for: server.id)
        }

        if preserveExisting {
            return true
        }

        return ServerCredentialStore.deletePassword(for: server.id)
    }

    private func persistSecurityFileChanges(for server: OPCUAServer, preserveExisting: Bool) -> Bool {
        persistSecurityFileChange(
            path: server.certificatePath,
            serverId: server.id,
            role: .clientCertificate,
            preserveExisting: preserveExisting
        ) &&
        persistSecurityFileChange(
            path: server.privateKeyPath,
            serverId: server.id,
            role: .privateKey,
            preserveExisting: preserveExisting
        ) &&
        persistSecurityFileChange(
            path: server.serverCertificatePath,
            serverId: server.id,
            role: .serverCertificate,
            preserveExisting: preserveExisting
        )
    }

    private func persistSecurityFileChange(
        path: String?,
        serverId: UUID,
        role: ServerSecurityFileRole,
        preserveExisting: Bool
    ) -> Bool {
        if let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ServerSecurityFileStore.savePath(path, for: serverId, role: role)
        }

        if preserveExisting {
            return true
        }

        return ServerSecurityFileStore.deletePath(for: serverId, role: role)
    }

    /// Save all servers (for bulk operations)
    func saveServers() {
        guard let context = modelContext else {
            print("❌ No model context available")
            return
        }

        do {
            try context.save()
            print("💾 Saved servers to SwiftData")
        } catch {
            print("❌ Failed to save servers: \(error)")
        }
    }

    // MARK: - Configuration Import/Export

    func exportConfiguration() -> ConfigurationBundle {
        // Strip credentials before exporting. Passwords are never written into
        // configuration bundles — they live only in Keychain on the originating
        // device.
        let sanitizedServers = servers.map { server -> OPCUAServer in
            var copy = server
            copy.password = nil
            copy.certificatePath = nil
            copy.privateKeyPath = nil
            copy.serverCertificatePath = nil
            return copy
        }
        let subscriptionConfigs = subscriptions.map { SubscriptionConfig(from: $0) }
        return ConfigurationBundle(
            version: 1,
            exportedAt: Date(),
            servers: sanitizedServers,
            subscriptions: subscriptionConfigs
        )
    }

    func importConfiguration(_ bundle: ConfigurationBundle) {
        for server in bundle.servers {
            saveServer(server, preserveExistingSensitiveReferences: true)
        }

        let serverIds = Set(servers.map { $0.id })
        for subscriptionConfig in bundle.subscriptions where serverIds.contains(subscriptionConfig.serverId) {
            saveSubscription(subscriptionConfig.toSubscription())
        }

        loadSubscriptions()
    }

    /// Delete a server from SwiftData
    func deleteServer(_ server: OPCUAServer) {
        guard let context = modelContext else {
            print("❌ No model context available")
            return
        }

        do {
            let id = server.id
            var descriptor = FetchDescriptor<ServerModel>(
                predicate: #Predicate { $0.id == id }
            )
            descriptor.fetchLimit = 1

            let existingServers = try context.fetch(descriptor)

            if let existingModel = existingServers.first {
                context.delete(existingModel)
                ServerCredentialStore.deletePassword(for: server.id)
                ServerSecurityFileStore.deleteAll(for: server.id)
                try context.save()
                print("🗑️ Deleted server: \(server.name)")
            }
            saveServersToDefaults(servers.filter { $0.id != server.id })

            // Reload servers to update the published array
            loadServers()
        } catch {
            print("❌ Failed to delete server: \(error)")
        }
    }

    /// Delete servers at indices
    func deleteServers(at offsets: IndexSet) {
        for index in offsets {
            let server = servers[index]
            deleteServer(server)
        }
    }

    /// Add a new server
    func addServer(_ server: OPCUAServer) {
        // If this is the first server, make it default
        var serverToAdd = server
        if servers.isEmpty {
            serverToAdd.isDefault = true
        }
        
        saveServer(serverToAdd)
        selectDefaultServerIfNeeded()
    }

    /// Update an existing server
    func updateServer(_ server: OPCUAServer) {
        saveServer(server)
    }

    private func loadServersFromDefaults() -> [OPCUAServer] {
        guard let data = UserDefaults.standard.data(forKey: serverDefaultsKey) else {
            return []
        }

        do {
            var savedServers = try JSONDecoder().decode([OPCUAServer].self, from: data)
            // Migrate any cleartext password that an older build wrote into the
            // fallback into Keychain, then clear it from in-memory state. The
            // next save will overwrite the plist without the password.
            var migrated = false
            var migrationFailed = false
            for index in savedServers.indices {
                if let password = savedServers[index].password, !password.isEmpty {
                    if ServerCredentialStore.password(for: savedServers[index].id) != nil ||
                        ServerCredentialStore.savePassword(password, for: savedServers[index].id) {
                        savedServers[index].password = nil
                        migrated = true
                    } else {
                        print("Failed to migrate fallback password for server \(savedServers[index].id) into Keychain; leaving fallback entry intact.")
                        migrationFailed = true
                    }
                }
                switch migrateFallbackSecurityFile(
                    path: &savedServers[index].certificatePath,
                    serverId: savedServers[index].id,
                    role: .clientCertificate
                ) {
                case .migrated:
                    migrated = true
                case .failed:
                    migrationFailed = true
                case .unchanged:
                    break
                }
                switch migrateFallbackSecurityFile(
                    path: &savedServers[index].privateKeyPath,
                    serverId: savedServers[index].id,
                    role: .privateKey
                ) {
                case .migrated:
                    migrated = true
                case .failed:
                    migrationFailed = true
                case .unchanged:
                    break
                }
                switch migrateFallbackSecurityFile(
                    path: &savedServers[index].serverCertificatePath,
                    serverId: savedServers[index].id,
                    role: .serverCertificate
                ) {
                case .migrated:
                    migrated = true
                case .failed:
                    migrationFailed = true
                case .unchanged:
                    break
                }
            }
            if migrated && !migrationFailed {
                saveServersToDefaults(savedServers)
            }
            print("📂 Loaded \(savedServers.count) servers from UserDefaults fallback")
            return savedServers
        } catch {
            print("❌ Failed to decode fallback servers: \(error)")
            return []
        }
    }

    private func saveServersToDefaults(_ servers: [OPCUAServer]) {
        // Strip credentials before writing to UserDefaults. Passwords belong in
        // Keychain only (see ServerCredentialStore); UserDefaults persists as
        // cleartext plist on disk.
        let sanitized = servers.map { server -> OPCUAServer in
            var copy = server
            copy.password = nil
            copy.certificatePath = nil
            copy.privateKeyPath = nil
            copy.serverCertificatePath = nil
            return copy
        }
        do {
            let data = try JSONEncoder().encode(sanitized)
            UserDefaults.standard.set(data, forKey: serverDefaultsKey)
            print("💾 Saved \(sanitized.count) servers to UserDefaults fallback")
        } catch {
            print("❌ Failed to encode fallback servers: \(error)")
        }
    }

    func clearServerFallbackDefaults() {
        UserDefaults.standard.removeObject(forKey: serverDefaultsKey)
    }

    private enum SecurityFileMigrationResult {
        case unchanged
        case migrated
        case failed
    }

    private func migrateFallbackSecurityFile(
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

        print("Failed to migrate fallback \(role.rawValue) path for server \(serverId) into Keychain; leaving fallback path intact.")
        return .failed
    }
    
    // MARK: - Subscription Persistence
    
    /// Load subscriptions from SwiftData
    func loadSubscriptions() {
        guard let persistence = subscriptionPersistence else {
            print("📂 No subscription persistence manager available")
            return
        }
        
        subscriptions = persistence.loadSubscriptions()
        print("📂 Loaded \(subscriptions.count) subscriptions from SwiftData")
    }
    
    /// Save a subscription
    func saveSubscription(_ subscription: Subscription) {
        guard let persistence = subscriptionPersistence else {
            print("❌ No subscription persistence manager available")
            return
        }
        
        persistence.saveSubscription(subscription, for: subscription.serverId)
        
        // Update local array
        if let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) {
            subscriptions[index] = subscription
        } else {
            subscriptions.append(subscription)
        }
        
        print("💾 Saved subscription: \(subscription.name)")
    }
    
    /// Delete a subscription
    func deleteSubscription(_ subscription: Subscription) {
        guard let persistence = subscriptionPersistence else {
            print("❌ No subscription persistence manager available")
            return
        }
        
        persistence.deleteSubscription(id: subscription.id)
        
        // Update local array
        subscriptions.removeAll { $0.id == subscription.id }
        
        print("🗑️ Deleted subscription: \(subscription.name)")
    }
    
    /// Add monitored item to a subscription
    func addMonitoredItem(_ item: MonitoredItem, to subscriptionId: UUID) {
        guard let persistence = subscriptionPersistence else {
            print("❌ No subscription persistence manager available")
            return
        }
        
        persistence.addMonitoredItem(item, to: subscriptionId)
        
        // Update local subscription
        if let index = subscriptions.firstIndex(where: { $0.id == subscriptionId }) {
            subscriptions[index].monitoredItems.append(item)
        }
        
        print("➕ Added monitored item: \(item.displayName)")
    }

    /// Remove monitored item from a subscription
    func removeMonitoredItem(_ item: MonitoredItem, from subscriptionId: UUID) {
        guard let persistence = subscriptionPersistence else {
            print("❌ No subscription persistence manager available")
            return
        }

        persistence.removeMonitoredItem(id: item.id)

        // Update local subscription
        if let index = subscriptions.firstIndex(where: { $0.id == subscriptionId }) {
            subscriptions[index].monitoredItems.removeAll { $0.id == item.id }
        }

        // Clear validation issues for the removed item
        lastSubscriptionValidationIssues.removeAll { $0.nodeId == item.nodeId }

        print("🗑️ Removed monitored item: \(item.displayName)")
    }
    
    
    /// Update monitored item value
    func updateMonitoredItemValue(nodeId: String, value: String, quality: NodeInfo.Quality) {
        guard let persistence = subscriptionPersistence else { return }
        
        persistence.updateMonitoredItemValue(nodeId: nodeId, value: value, quality: quality)
        
        // Update local subscriptions
        for (subIndex, subscription) in subscriptions.enumerated() {
            for (itemIndex, item) in subscription.monitoredItems.enumerated() {
                if item.nodeId == nodeId {
                    subscriptions[subIndex].monitoredItems[itemIndex].currentValue = value
                    subscriptions[subIndex].monitoredItems[itemIndex].timestamp = Date()
                    subscriptions[subIndex].monitoredItems[itemIndex].quality = quality
                }
            }
        }
    }

    // MARK: - Validation
    
    /// Validate all subscriptions and update validation issues
    func validateCurrentSubscriptions() {
        let subscriptionsSnapshot = subscriptions
        let serversSnapshot = servers
        let clientsSnapshot = connectionManager.connectedClients

        Task { @MainActor in
            var allValidationIssues: [MonitoredItemValidation] = []

            for subscription in subscriptionsSnapshot {
                guard let server = serversSnapshot.first(where: { $0.id == subscription.serverId }),
                      let client = clientsSnapshot[server.id.uuidString] else {
                    continue
                }

                let validations = await OPCUAClientWork.run {
                    SubscriptionValidator.validateSubscription(subscription, client: client)
                }
                let invalidValidations = validations.filter { !$0.isValid }
                allValidationIssues.append(contentsOf: invalidValidations)
            }

            self.lastSubscriptionValidationIssues = allValidationIssues
        }
    }

    enum MainTab: String, CaseIterable, Identifiable {
        case servers = "Servers"
        case browse = "Address Space"
        case readWrite = "Read / Write"
        case subscriptions = "Subscriptions"
        case monitor = "Live Monitor"
        case analytics = "Analytics"
        case alarms = "Alarms & Events"
        case history = "History"
        case diagnostics = "Diagnostics"
        case security = "Security"
        case reports = "Reports"
        case settings = "Settings"

        var id: String { self.rawValue }

        var systemImage: String {
            switch self {
            case .servers: return "server.rack"
            case .browse: return "square.stack.3d.up"
            case .readWrite: return "pencil.and.list.clipboard"
            case .subscriptions: return "bell.badge.fill"
            case .monitor: return "waveform.path.ecg.rectangle"
            case .analytics: return "chart.xyaxis.line"
            case .alarms: return "bell.and.waves.left.and.right"
            case .history: return "clock.arrow.circlepath"
            case .diagnostics: return "stethoscope"
            case .security: return "lock.shield"
            case .reports: return "doc.text.magnifyingglass"
            case .settings: return "gearshape"
            }
        }
    }
}

private extension Array where Element == OPCUAServer {
    func replacing(_ server: OPCUAServer) -> [OPCUAServer] {
        var updated = self
        if let index = updated.firstIndex(where: { $0.id == server.id }) {
            updated[index] = server
        } else {
            updated.append(server)
        }
        return updated
    }
}
