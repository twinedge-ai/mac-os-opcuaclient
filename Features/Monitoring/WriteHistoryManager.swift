import Foundation
import Combine

struct WriteHistoryEntry: Identifiable, Equatable {
    let id: UUID
    let serverId: UUID
    let serverName: String
    let nodeId: String
    let nodeDisplayName: String
    let value: String
    let dataType: String?
    let timestamp: Date
    let success: Bool
    let errorMessage: String?

    init(
        id: UUID = UUID(),
        serverId: UUID,
        serverName: String,
        nodeId: String,
        nodeDisplayName: String,
        value: String,
        dataType: String?,
        timestamp: Date = Date(),
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.serverId = serverId
        self.serverName = serverName
        self.nodeId = nodeId
        self.nodeDisplayName = nodeDisplayName
        self.value = value
        self.dataType = dataType
        self.timestamp = timestamp
        self.success = success
        self.errorMessage = errorMessage
    }
}

@MainActor
class WriteHistoryManager: ObservableObject {
    @Published private(set) var entries: [WriteHistoryEntry] = []

    private let maxEntries = 200

    func addEntry(
        server: OPCUAServer,
        nodeId: String,
        nodeDisplayName: String?,
        value: String,
        dataType: String?,
        success: Bool,
        errorMessage: String? = nil
    ) {
        let entry = WriteHistoryEntry(
            serverId: server.id,
            serverName: server.name,
            nodeId: nodeId,
            nodeDisplayName: nodeDisplayName ?? nodeId,
            value: value,
            dataType: dataType,
            success: success,
            errorMessage: errorMessage
        )

        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }

    func entries(for nodeId: String, serverId: UUID?) -> [WriteHistoryEntry] {
        entries.filter { entry in
            entry.nodeId == nodeId && (serverId == nil || entry.serverId == serverId)
        }
    }

    func clearHistory(for nodeId: String, serverId: UUID?) {
        entries.removeAll { entry in
            entry.nodeId == nodeId && (serverId == nil || entry.serverId == serverId)
        }
    }
}
