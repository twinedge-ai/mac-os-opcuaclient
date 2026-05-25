import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ConfigurationBundle: Codable {
    var version: Int
    var exportedAt: Date
    var servers: [OPCUAServer]
    var subscriptions: [SubscriptionConfig]
}

struct SubscriptionConfig: Codable {
    var id: UUID
    var name: String
    var serverId: UUID
    var publishingInterval: Double
    var priority: Int
    var isActive: Bool
    var monitoredItems: [MonitoredItemConfig]

    init(from subscription: Subscription) {
        id = subscription.id
        name = subscription.name
        serverId = subscription.serverId
        publishingInterval = subscription.publishingInterval
        priority = subscription.priority
        isActive = subscription.isActive
        monitoredItems = subscription.monitoredItems.map { MonitoredItemConfig(from: $0) }
    }

    func toSubscription() -> Subscription {
        Subscription(
            id: id,
            name: name,
            serverId: serverId,
            publishingInterval: publishingInterval,
            priority: priority,
            isActive: isActive,
            monitoredItems: monitoredItems.map { $0.toMonitoredItem() }
        )
    }
}

struct MonitoredItemConfig: Codable {
    var id: UUID
    var nodeId: String
    var displayName: String
    var samplingInterval: Double
    var samplingPreset: SamplingPreset
    var deadbandType: DeadbandType
    var deadbandValue: Double
    var queueSize: Int
    var discardOldest: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        nodeId = try container.decode(String.self, forKey: .nodeId)
        displayName = try container.decode(String.self, forKey: .displayName)
        samplingInterval = try container.decode(Double.self, forKey: .samplingInterval)
        samplingPreset = try container.decodeIfPresent(SamplingPreset.self, forKey: .samplingPreset) ?? .standard
        deadbandType = try container.decodeIfPresent(DeadbandType.self, forKey: .deadbandType) ?? .none
        deadbandValue = try container.decodeIfPresent(Double.self, forKey: .deadbandValue) ?? 0
        queueSize = try container.decode(Int.self, forKey: .queueSize)
        discardOldest = try container.decode(Bool.self, forKey: .discardOldest)
    }

    init(from item: MonitoredItem) {
        id = item.id
        nodeId = item.nodeId
        displayName = item.displayName
        samplingInterval = item.samplingInterval
        samplingPreset = item.samplingPreset
        deadbandType = item.deadbandType
        deadbandValue = item.deadbandValue
        queueSize = item.queueSize
        discardOldest = item.discardOldest
    }

    func toMonitoredItem() -> MonitoredItem {
        MonitoredItem(
            id: id,
            nodeId: nodeId,
            displayName: displayName,
            samplingInterval: samplingInterval,
            samplingPreset: samplingPreset,
            deadbandType: deadbandType,
            deadbandValue: deadbandValue,
            queueSize: queueSize,
            discardOldest: discardOldest,
            currentValue: nil,
            timestamp: nil,
            quality: .uncertain
        )
    }
}

enum ConfigurationCodec {
    static func encode(_ bundle: ConfigurationBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    static func decode(_ data: Data) throws -> ConfigurationBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ConfigurationBundle.self, from: data)
    }
}

struct ConfigurationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var bundle: ConfigurationBundle

    init(bundle: ConfigurationBundle) {
        self.bundle = bundle
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        bundle = try ConfigurationCodec.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try ConfigurationCodec.encode(bundle)
        return FileWrapper(regularFileWithContents: data)
    }
}
