import Foundation
import SwiftData

@Model
final class MonitoredItemModel {
    @Attribute(.unique) var id: UUID
    var nodeId: String
    var displayName: String
    var samplingInterval: Double
    var samplingPreset: String
    var deadbandType: String
    var deadbandValue: Double
    var queueSize: UInt32
    var discardOldest: Bool
    
    // Value tracking
    var currentValue: String?
    var lastUpdateTimestamp: Date?
    var quality: String
    
    // Historical data (last N values for charts)
    var historicalValues: [ValueSnapshot]
    
    var createdAt: Date
    var updatedAt: Date
    
    // Relationship to subscription
    var subscription: SubscriptionModel?
    
    init(
        id: UUID = UUID(),
        nodeId: String,
        displayName: String,
        samplingInterval: Double = 1000.0,
        samplingPreset: String = SamplingPreset.standard.rawValue,
        deadbandType: String = DeadbandType.none.rawValue,
        deadbandValue: Double = 0,
        queueSize: UInt32 = 10,
        discardOldest: Bool = true,
        currentValue: String? = nil,
        quality: String = "Uncertain"
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
        self.lastUpdateTimestamp = currentValue != nil ? Date() : nil
        self.quality = quality
        self.historicalValues = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    /// Convert to MonitoredItem struct for use with existing code
    func toMonitoredItem() -> MonitoredItem {
        // Persisted values are historical last-known samples, not a guarantee that the
        // current OPC UA session is live. Start loaded items in a waiting state and let
        // connection restore/refresh populate fresh values from the server.
        MonitoredItem(
            id: id,
            nodeId: nodeId,
            displayName: displayName,
            samplingInterval: samplingInterval,
            samplingPreset: SamplingPreset(rawValue: samplingPreset) ?? .standard,
            deadbandType: DeadbandType(rawValue: deadbandType) ?? .none,
            deadbandValue: deadbandValue,
            queueSize: Int(queueSize),
            discardOldest: discardOldest,
            currentValue: nil,
            timestamp: nil,
            quality: .uncertain
        )
    }
    
    /// Update from MonitoredItem struct
    func update(from item: MonitoredItem) {
        self.nodeId = item.nodeId
        self.displayName = item.displayName
        self.samplingInterval = item.samplingInterval
        self.samplingPreset = item.samplingPreset.rawValue
        self.deadbandType = item.deadbandType.rawValue
        self.deadbandValue = item.deadbandValue
        self.queueSize = UInt32(item.queueSize)
        self.discardOldest = item.discardOldest
        self.currentValue = item.currentValue
        self.lastUpdateTimestamp = item.timestamp
        self.quality = item.quality.rawValue
        self.updatedAt = Date()
        
        // Add to historical values if there's a new value
        if let value = item.currentValue, let timestamp = item.timestamp {
            addHistoricalValue(value: value, timestamp: timestamp)
        }
    }
    
    /// Create MonitoredItemModel from MonitoredItem struct
    static func from(_ item: MonitoredItem) -> MonitoredItemModel {
        MonitoredItemModel(
            id: item.id,
            nodeId: item.nodeId,
            displayName: item.displayName,
            samplingInterval: item.samplingInterval,
            samplingPreset: item.samplingPreset.rawValue,
            deadbandType: item.deadbandType.rawValue,
            deadbandValue: item.deadbandValue,
            queueSize: UInt32(item.queueSize),
            discardOldest: item.discardOldest,
            currentValue: item.currentValue,
            quality: item.quality.rawValue
        )
    }
    
    /// Add a new value to historical data (keeps last 100 values)
    func addHistoricalValue(value: String, timestamp: Date) {
        let snapshot = ValueSnapshot(value: value, timestamp: timestamp)
        historicalValues.append(snapshot)
        
        // Keep only last 100 values for performance
        if historicalValues.count > 100 {
            historicalValues.removeFirst(historicalValues.count - 100)
        }
    }
}

/// Value snapshot for historical data
struct ValueSnapshot: Codable {
    let value: String
    let timestamp: Date
}
