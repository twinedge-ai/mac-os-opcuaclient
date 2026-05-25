import Foundation
import SwiftData

@Model
final class SubscriptionModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var publishingInterval: Double
    var priority: Int
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    
    // Relationship to server
    var server: ServerModel?
    
    // Relationship to monitored items
    @Relationship(deleteRule: .cascade, inverse: \MonitoredItemModel.subscription)
    var monitoredItems: [MonitoredItemModel]
    
    init(
        id: UUID = UUID(),
        name: String,
        publishingInterval: Double = 1000.0,
        priority: Int = 1,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.publishingInterval = publishingInterval
        self.priority = priority
        self.isActive = isActive
        self.createdAt = Date()
        self.updatedAt = Date()
        self.monitoredItems = []
    }
    
    /// Convert to Subscription struct for use with existing code
    func toSubscription() -> Subscription {
        Subscription(
            id: id,
            name: name,
            serverId: server?.id ?? UUID(),
            publishingInterval: publishingInterval,
            priority: priority,
            isActive: isActive,
            monitoredItems: monitoredItems.map { $0.toMonitoredItem() }
        )
    }
    
    /// Update from Subscription struct
    func update(from subscription: Subscription) {
        self.name = subscription.name
        self.publishingInterval = subscription.publishingInterval
        self.priority = subscription.priority
        self.isActive = subscription.isActive
        self.updatedAt = Date()
    }
    
    /// Create SubscriptionModel from Subscription struct
    static func from(_ subscription: Subscription) -> SubscriptionModel {
        let model = SubscriptionModel(
            id: subscription.id,
            name: subscription.name,
            publishingInterval: subscription.publishingInterval,
            priority: subscription.priority,
            isActive: subscription.isActive
        )
        
        // Create monitored item models
        model.monitoredItems = subscription.monitoredItems.map { MonitoredItemModel.from($0) }
        
        return model
    }
}
