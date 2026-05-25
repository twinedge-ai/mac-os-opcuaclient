import Foundation
import SwiftData

@MainActor
class SubscriptionPersistenceManager {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Subscription Operations
    
    /// Load all subscriptions from persistent storage
    func loadSubscriptions() -> [Subscription] {
        let descriptor = FetchDescriptor<SubscriptionModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        
        do {
            let models = try modelContext.fetch(descriptor)
            return models.map { $0.toSubscription() }
        } catch {
            print("Failed to load subscriptions: \(error)")
            return []
        }
    }
    
    /// Load subscriptions for a specific server
    func loadSubscriptions(for serverId: UUID) -> [Subscription] {
        let descriptor = FetchDescriptor<SubscriptionModel>(
            predicate: #Predicate { $0.server?.id == serverId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        
        do {
            let models = try modelContext.fetch(descriptor)
            return models.map { $0.toSubscription() }
        } catch {
            print("Failed to load subscriptions for server \(serverId): \(error)")
            return []
        }
    }
    
    /// Save a new subscription
    func saveSubscription(_ subscription: Subscription, for serverId: UUID) {
        // Find the server model
        let serverDescriptor = FetchDescriptor<ServerModel>(
            predicate: #Predicate { $0.id == serverId }
        )
        
        do {
            let servers = try modelContext.fetch(serverDescriptor)
            guard let server = servers.first else {
                print("Server not found for ID: \(serverId)")
                return
            }
            
            // Check if subscription already exists
            if let existingModel = findSubscriptionModel(by: subscription.id) {
                // Update existing
                existingModel.update(from: subscription)
                
                // Update monitored items
                updateMonitoredItems(for: existingModel, from: subscription)
            } else {
                // Create new
                let model = SubscriptionModel.from(subscription)
                model.server = server
                
                // Set subscription reference for monitored items
                for itemModel in model.monitoredItems {
                    itemModel.subscription = model
                }
                
                modelContext.insert(model)
                server.subscriptions.append(model)
            }
            
            try modelContext.save()
        } catch {
            print("Failed to save subscription: \(error)")
        }
    }
    
    /// Update an existing subscription
    func updateSubscription(_ subscription: Subscription) {
        guard let model = findSubscriptionModel(by: subscription.id) else {
            print("Subscription not found for update: \(subscription.id)")
            return
        }
        
        model.update(from: subscription)
        updateMonitoredItems(for: model, from: subscription)
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to update subscription: \(error)")
        }
    }
    
    /// Delete a subscription
    func deleteSubscription(id: UUID) {
        guard let model = findSubscriptionModel(by: id) else {
            print("Subscription not found for deletion: \(id)")
            return
        }
        
        modelContext.delete(model)
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to delete subscription: \(error)")
        }
    }
    
    // MARK: - Monitored Item Operations
    
    /// Add a monitored item to a subscription
    func addMonitoredItem(_ item: MonitoredItem, to subscriptionId: UUID) {
        guard let subscriptionModel = findSubscriptionModel(by: subscriptionId) else {
            print("Subscription not found: \(subscriptionId)")
            return
        }
        
        let itemModel = MonitoredItemModel.from(item)
        itemModel.subscription = subscriptionModel
        subscriptionModel.monitoredItems.append(itemModel)
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to add monitored item: \(error)")
        }
    }
    
    /// Update a monitored item's value
    func updateMonitoredItemValue(nodeId: String, value: String, quality: NodeInfo.Quality) {
        let descriptor = FetchDescriptor<MonitoredItemModel>(
            predicate: #Predicate { $0.nodeId == nodeId }
        )
        
        do {
            let items = try modelContext.fetch(descriptor)
            for item in items {
                item.currentValue = value
                item.lastUpdateTimestamp = Date()
                item.quality = quality.rawValue
                item.addHistoricalValue(value: value, timestamp: Date())
                item.updatedAt = Date()
            }
            
            try modelContext.save()
        } catch {
            print("Failed to update monitored item value: \(error)")
        }
    }
    
    /// Remove a monitored item
    func removeMonitoredItem(id: UUID) {
        let descriptor = FetchDescriptor<MonitoredItemModel>(
            predicate: #Predicate { $0.id == id }
        )
        
        do {
            let items = try modelContext.fetch(descriptor)
            for item in items {
                modelContext.delete(item)
            }
            
            try modelContext.save()
        } catch {
            print("Failed to remove monitored item: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func findSubscriptionModel(by id: UUID) -> SubscriptionModel? {
        let descriptor = FetchDescriptor<SubscriptionModel>(
            predicate: #Predicate { $0.id == id }
        )
        
        do {
            let models = try modelContext.fetch(descriptor)
            return models.first
        } catch {
            print("Failed to find subscription model: \(error)")
            return nil
        }
    }
    
    private func updateMonitoredItems(for subscriptionModel: SubscriptionModel, from subscription: Subscription) {
        // Remove items that are no longer in the subscription
        let currentItemIds = Set(subscription.monitoredItems.map { $0.id })
        subscriptionModel.monitoredItems.removeAll { !currentItemIds.contains($0.id) }
        
        // Update existing and add new items
        for item in subscription.monitoredItems {
            if let existingItem = subscriptionModel.monitoredItems.first(where: { $0.id == item.id }) {
                existingItem.update(from: item)
            } else {
                let newItem = MonitoredItemModel.from(item)
                newItem.subscription = subscriptionModel
                subscriptionModel.monitoredItems.append(newItem)
            }
        }
    }
    
    // MARK: - Batch Operations
    
    /// Load all monitored items for analytics
    func loadAllMonitoredItems() -> [MonitoredItem] {
        let descriptor = FetchDescriptor<MonitoredItemModel>(
            sortBy: [SortDescriptor(\.displayName, order: .forward)]
        )
        
        do {
            let models = try modelContext.fetch(descriptor)
            return models.map { $0.toMonitoredItem() }
        } catch {
            print("Failed to load monitored items: \(error)")
            return []
        }
    }
    
    /// Get historical values for a node
    func getHistoricalValues(for nodeId: String) -> [ValueSnapshot] {
        let descriptor = FetchDescriptor<MonitoredItemModel>(
            predicate: #Predicate { $0.nodeId == nodeId }
        )
        
        do {
            let items = try modelContext.fetch(descriptor)
            return items.first?.historicalValues ?? []
        } catch {
            print("Failed to get historical values: \(error)")
            return []
        }
    }
}