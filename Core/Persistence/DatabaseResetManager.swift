import Foundation
import SwiftData

/// Manager for resetting the database and clearing all saved data
@MainActor
class DatabaseResetManager {
    
    /// Reset all stored data including servers, subscriptions, and monitored items
    static func resetDatabase(modelContext: ModelContext) async throws {
        print("🗑️ [Database] Starting database reset...")

        // 1. Delete all monitored items
        let monitoredItemsDescriptor = FetchDescriptor<MonitoredItemModel>()
        let monitoredItems = try modelContext.fetch(monitoredItemsDescriptor)
        for item in monitoredItems {
            modelContext.delete(item)
        }
        print("   Deleted \(monitoredItems.count) monitored items")

        // 2. Delete all subscriptions
        let subscriptionsDescriptor = FetchDescriptor<SubscriptionModel>()
        let subscriptions = try modelContext.fetch(subscriptionsDescriptor)
        for subscription in subscriptions {
            modelContext.delete(subscription)
        }
        print("   Deleted \(subscriptions.count) subscriptions")

        // 3. Delete all servers and their Keychain credentials. Skipping the
        // Keychain delete would leave orphaned password entries that survive
        // even after the user has wiped local data.
        let serversDescriptor = FetchDescriptor<ServerModel>()
        let servers = try modelContext.fetch(serversDescriptor)
        for server in servers {
            ServerCredentialStore.deletePassword(for: server.id)
            ServerSecurityFileStore.deleteAll(for: server.id)
            modelContext.delete(server)
        }
        print("   Deleted \(servers.count) servers")

        // 4. Save changes
        try modelContext.save()

        print("✅ [Database] Reset completed successfully")
    }
    
    /// Reset only subscriptions and monitored items, keeping servers
    static func resetSubscriptions(modelContext: ModelContext) async throws {
        print("🗑️ [Database] Starting subscription reset...")
        
        // 1. Delete all monitored items
        let monitoredItemsDescriptor = FetchDescriptor<MonitoredItemModel>()
        let monitoredItems = try modelContext.fetch(monitoredItemsDescriptor)
        for item in monitoredItems {
            modelContext.delete(item)
        }
        print("   Deleted \(monitoredItems.count) monitored items")
        
        // 2. Delete all subscriptions
        let subscriptionsDescriptor = FetchDescriptor<SubscriptionModel>()
        let subscriptions = try modelContext.fetch(subscriptionsDescriptor)
        for subscription in subscriptions {
            modelContext.delete(subscription)
        }
        print("   Deleted \(subscriptions.count) subscriptions")
        
        // 3. Save changes
        try modelContext.save()
        
        print("✅ [Database] Subscription reset completed")
    }
    
    /// Reset only monitored items, keeping servers and subscriptions structure
    static func resetMonitoredItems(modelContext: ModelContext) async throws {
        print("🗑️ [Database] Starting monitored items reset...")
        
        // 1. Delete all monitored items
        let monitoredItemsDescriptor = FetchDescriptor<MonitoredItemModel>()
        let monitoredItems = try modelContext.fetch(monitoredItemsDescriptor)
        for item in monitoredItems {
            modelContext.delete(item)
        }
        print("   Deleted \(monitoredItems.count) monitored items")
        
        // 2. Clear monitored items arrays in subscriptions
        let subscriptionsDescriptor = FetchDescriptor<SubscriptionModel>()
        let subscriptions = try modelContext.fetch(subscriptionsDescriptor)
        for subscription in subscriptions {
            subscription.monitoredItems.removeAll()
        }
        
        // 3. Save changes
        try modelContext.save()
        
        print("✅ [Database] Monitored items reset completed")
    }
    
    /// Get database statistics
    static func getDatabaseStats(modelContext: ModelContext) throws -> DatabaseStats {
        let serversDescriptor = FetchDescriptor<ServerModel>()
        let subscriptionsDescriptor = FetchDescriptor<SubscriptionModel>()
        let monitoredItemsDescriptor = FetchDescriptor<MonitoredItemModel>()
        
        let serverCount = try modelContext.fetch(serversDescriptor).count
        let subscriptionCount = try modelContext.fetch(subscriptionsDescriptor).count
        let monitoredItemCount = try modelContext.fetch(monitoredItemsDescriptor).count
        
        return DatabaseStats(
            serverCount: serverCount,
            subscriptionCount: subscriptionCount,
            monitoredItemCount: monitoredItemCount
        )
    }
}

/// Database statistics structure
struct DatabaseStats {
    let serverCount: Int
    let subscriptionCount: Int
    let monitoredItemCount: Int
    
    var totalCount: Int {
        serverCount + subscriptionCount + monitoredItemCount
    }
    
    var description: String {
        "Servers: \(serverCount), Subscriptions: \(subscriptionCount), Monitored Items: \(monitoredItemCount)"
    }
}

/// Extension to AppState for database reset functionality
extension AppState {
    
    /// Reset the entire database
    func resetDatabase() async {
        guard let modelContext = self.modelContext else {
            print("❌ [Database] Cannot reset - no model context available")
            return
        }
        
        do {
            // Disconnect all active connections first
            connectionManager.disconnectAll()
            
            // Reset the database
            try await DatabaseResetManager.resetDatabase(modelContext: modelContext)
            
            // Clear in-memory state
            await MainActor.run {
                self.clearServerFallbackDefaults()
                self.servers.removeAll()
                self.subscriptions.removeAll()
                self.selectedServer = nil
                self.lastSubscriptionValidationIssues.removeAll()
            }

            print("✅ [AppState] Database reset completed")
            
        } catch {
            print("❌ [Database] Failed to reset database: \(error)")
        }
    }
    
    /// Reset only subscriptions
    func resetSubscriptions() async {
        guard let modelContext = self.modelContext else {
            print("❌ [Database] Cannot reset - no model context available")
            return
        }
        
        do {
            // Disconnect all to stop subscriptions
            connectionManager.disconnectAll()
            
            // Reset subscriptions in database
            try await DatabaseResetManager.resetSubscriptions(modelContext: modelContext)
            
            // Clear in-memory subscriptions
            await MainActor.run {
                self.subscriptions.removeAll()
                self.lastSubscriptionValidationIssues.removeAll()
            }
            
            print("✅ [AppState] Subscriptions reset completed")
            
        } catch {
            print("❌ [Database] Failed to reset subscriptions: \(error)")
        }
    }
    
    /// Get current database statistics
    func getDatabaseStats() -> DatabaseStats? {
        guard let modelContext = self.modelContext else { return nil }
        
        do {
            return try DatabaseResetManager.getDatabaseStats(modelContext: modelContext)
        } catch {
            print("❌ [Database] Failed to get stats: \(error)")
            return nil
        }
    }
}
