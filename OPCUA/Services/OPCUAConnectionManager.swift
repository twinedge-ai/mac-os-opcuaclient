import Foundation
import Combine

@MainActor
class OPCUAConnectionManager: ObservableObject {
    @Published var connectedClients: [String: SimpleOpcUaClient] = [:]
    @Published var connectionErrors: [String: ConnectionErrorDetail] = [:]
    @Published var connectionQualities: [String: ConnectionQuality] = [:]

    // Non-published connection status cache for UI queries
    private var connectionStatusCache: [String: ConnectionStatus] = [:]
    private var reconnectAttempts: [String: Int] = [:]
    private var healthFailureCounts: [String: Int] = [:]
    private var healthMonitorTasks: [String: Task<Void, Never>] = [:]
    private var reconnectTasks: [String: Task<Void, Never>] = [:]
    private var networkTraceRelays: [String: OPCUANetworkTraceRelay] = [:]
    private var manualDisconnects: Set<String> = []

    private let networkTraceRelayDefaultsKey = "opcua.client.networkTraceRelay.enabled"
    private let healthCheckInterval: TimeInterval = 6
    private let maxReconnectDelay: TimeInterval = 30

    // Reference to diagnostics manager for logging
    private var diagnostics: DiagnosticsManager { DiagnosticsManager.shared }
    private let alarmManager = AlarmEventManager.shared
    private var lastEventLogByNode: [String: Date] = [:]
    private let dataChangeLogInterval: TimeInterval = 10
    
    // Reference to AppState for updating monitored items
    weak var appState: AppState?

    // MARK: - Connection Management

    func connectToServer(_ server: OPCUAServer) async -> Bool {
        guard server.networkSchema == .opcTcp else {
            let detail = ConnectionErrorDetail(
                message: "Only opc.tcp endpoints are supported by this build.",
                hints: [
                    "Use an opc.tcp endpoint",
                    "Remove OPC WebSocket profiles until WSS transport support is added"
                ],
                actions: [.editServer]
            )
            let serverId = server.id.uuidString
            connectionErrors[serverId] = detail
            connectionStatusCache[serverId] = .error
            connectionQualities[serverId] = .poor
            diagnostics.log("Cannot connect to \(server.name): \(detail.message)", level: .error, component: "Connection")
            diagnostics.recordMessageError()
            appState?.notifyConnectionStateChanged()
            NotificationCenter.default.post(name: .opcuaConnectionChanged, object: nil)
            return false
        }

        var endpoint = server.endpoint

        // Force IPv4 by replacing localhost with 127.0.0.1
        endpoint = endpoint.replacingOccurrences(of: "://localhost:", with: "://127.0.0.1:")
        endpoint = endpoint.replacingOccurrences(of: "://localhost/", with: "://127.0.0.1/")

        // Check if already connected
        if let existingClient = connectedClients[server.id.uuidString],
           existingClient.connectionStatus {
            diagnostics.log("Already connected to \(server.name)", level: .debug, component: "Connection")
            return true
        }

        diagnostics.log("Attempting to connect to \(server.name) at \(endpoint)", level: .info, component: "Connection")

        let serverId = server.id.uuidString
        var client = SimpleOpcUaClient()
        let relayEndpoint = isNetworkTraceRelayEnabled ? startNetworkTraceRelay(for: server, endpoint: endpoint) : nil
        let connectionEndpoint = relayEndpoint ?? endpoint
        recordProtocolEvent(type: "HEL", direction: .sent, size: 56, serverId: serverId)

        var success = await OPCUAClientWork.run {
            client.connect(to: connectionEndpoint, server: server)
        }

        if !success, relayEndpoint != nil {
            stopNetworkTraceRelay(forId: serverId)
            diagnostics.log(
                "Network byte capture relay could not complete the OPC UA connection for \(server.name); retrying the direct endpoint.",
                level: .warning,
                component: "NetworkTrace"
            )
            client = SimpleOpcUaClient()
            recordProtocolEvent(type: "HEL", direction: .sent, size: 56, serverId: serverId)
            success = await OPCUAClientWork.run {
                client.connect(to: endpoint, server: server)
            }
        }

        if success {
            await MainActor.run {
                print("📁 Storing client for server: \(server.name) (ID: \(server.id.uuidString))")
                self.connectedClients[server.id.uuidString] = client
                self.connectionErrors.removeValue(forKey: server.id.uuidString)
                self.connectionStatusCache[server.id.uuidString] = .connected
                self.connectionQualities[server.id.uuidString] = .unknown
                self.healthFailureCounts[server.id.uuidString] = 0
                self.reconnectAttempts[server.id.uuidString] = 0
                self.manualDisconnects.remove(server.id.uuidString)
                self.appState?.selectedServer = server
                self.appState?.notifyConnectionStateChanged()
                print("📊 Connected clients count: \(self.connectedClients.count)")

                // Log to diagnostics
                diagnostics.log("Successfully connected to \(server.name)", level: .info, component: "Connection")
                recordProtocolEvent(type: "ACK", direction: .received, size: 28, serverId: serverId)
                recordProtocolEvent(type: "OPN", direction: .sent, size: 132, serverId: serverId)
                recordProtocolEvent(type: "OPN", direction: .received, size: 148, serverId: serverId)

                // Post notification for UI updates
                NotificationCenter.default.post(name: .opcuaConnectionChanged, object: nil)
            }

            alarmManager.logEvent(SystemEvent(
                message: "Connected to server",
                type: .connection,
                source: server.name,
                data: ["endpoint": endpoint]
            ))

            startHealthMonitor(for: server, client: client)

            // Restore existing subscriptions for this server from persistence
            await restoreSubscriptions(for: server)

            return true
        } else {
            await MainActor.run {
                let errorDetail = client.lastErrorDetail ?? self.defaultConnectionFailureDetail(for: server, endpoint: endpoint)
                self.connectionErrors[server.id.uuidString] = errorDetail
                self.connectionStatusCache[server.id.uuidString] = .error
                self.connectionQualities[server.id.uuidString] = .poor
                self.appState?.notifyConnectionStateChanged()

                // Log to diagnostics
                diagnostics.log("Failed to connect to \(server.name): \(errorDetail.message)", level: .error, component: "Connection")
                diagnostics.recordMessageError()
                stopNetworkTraceRelay(forId: serverId)

                // Post notification for UI updates
                NotificationCenter.default.post(name: .opcuaConnectionChanged, object: nil)
            }

            alarmManager.addAlarm(Alarm(
                message: "Connection failed for \(server.name)",
                severity: .high,
                source: server.name
            ))

            alarmManager.logEvent(SystemEvent(
                message: "Connection failed",
                type: .connection,
                source: server.name,
                data: ["endpoint": endpoint]
            ))

            scheduleReconnect(for: server)
            return false
        }
    }
    
    func disconnectFromServer(_ server: OPCUAServer) {
        manualDisconnects.insert(server.id.uuidString)
        stopHealthMonitor(for: server)
        cancelReconnect(for: server)
        guard let client = connectedClients[server.id.uuidString] else { return }

        diagnostics.log("Disconnecting from \(server.name)", level: .info, component: "Connection")
        recordProtocolEvent(type: "CLO", direction: .sent, size: 24, serverId: server.id.uuidString)

        Task {
            await OPCUAClientWork.run {
                client.disconnect()
            }
            await MainActor.run {
                self.connectedClients.removeValue(forKey: server.id.uuidString)
                self.connectionErrors.removeValue(forKey: server.id.uuidString)
                self.connectionStatusCache[server.id.uuidString] = .disconnected
                self.connectionQualities[server.id.uuidString] = .unknown
                self.appState?.notifyConnectionStateChanged()

                diagnostics.log("Disconnected from \(server.name)", level: .info, component: "Connection")
                recordProtocolEvent(type: "CLO", direction: .received, size: 24, serverId: server.id.uuidString)
                stopNetworkTraceRelay(forId: server.id.uuidString)

                // Post notification for UI updates
                NotificationCenter.default.post(name: .opcuaConnectionChanged, object: nil)
            }
        }

        alarmManager.logEvent(SystemEvent(
            message: "Disconnected from server",
            type: .connection,
            source: server.name
        ))
    }
    
    func disconnectAll() {
        manualDisconnects = Set(connectedClients.keys)
        for (serverId, _) in connectedClients {
            stopHealthMonitor(forId: serverId)
            cancelReconnect(forId: serverId)
        }
        let clients = Array(connectedClients.values)
        stopAllNetworkTraceRelays()
        Task {
            await OPCUAClientWork.run {
                for client in clients {
                    client.disconnect()
                }
            }
            await MainActor.run {
                self.connectedClients.removeAll()
                self.connectionErrors.removeAll()
                self.connectionStatusCache.removeAll()
                self.connectionQualities.removeAll()
                self.appState?.selectedServer = nil
                self.appState?.notifyConnectionStateChanged()
            }
        }
    }

    // MARK: - Network Trace Relay

    private var isNetworkTraceRelayEnabled: Bool {
        UserDefaults.standard.bool(forKey: networkTraceRelayDefaultsKey)
    }

    private func startNetworkTraceRelay(for server: OPCUAServer, endpoint: String) -> String? {
        let serverId = server.id.uuidString
        guard server.networkSchema == .opcTcp,
              let target = OPCUANetworkTraceRelay.Target.parse(endpointURL: endpoint, defaultPort: server.port) else {
            return nil
        }

        stopNetworkTraceRelay(forId: serverId)

        let relay = OPCUANetworkTraceRelay(serverName: server.name, target: target)
        do {
            let localEndpoint = try relay.start()
            networkTraceRelays[serverId] = relay
            diagnostics.log(
                "Network byte capture relay listening at \(localEndpoint), forwarding to \(endpoint)",
                level: .info,
                component: "NetworkTrace"
            )
            return localEndpoint
        } catch {
            diagnostics.log(
                "Network byte capture relay unavailable for \(server.name): \(error.localizedDescription)",
                level: .warning,
                component: "NetworkTrace"
            )
            return nil
        }
    }

    private func stopNetworkTraceRelay(forId serverId: String) {
        guard let relay = networkTraceRelays.removeValue(forKey: serverId) else {
            return
        }

        relay.stop()
        diagnostics.log("Stopped network byte capture relay", level: .debug, component: "NetworkTrace")
    }

    private func stopAllNetworkTraceRelays() {
        let relays = networkTraceRelays.values
        networkTraceRelays.removeAll()
        for relay in relays {
            relay.stop()
        }
    }

    private func recordProtocolEvent(type: String, direction: PacketDirection, size: Int, serverId: String) {
        guard networkTraceRelays[serverId]?.isRunning != true else {
            return
        }

        diagnostics.recordPacket(type: type, direction: direction, size: size, data: nil)
    }

    // MARK: - Connection Health Monitoring

    func getConnectionQuality(for server: OPCUAServer) -> ConnectionQuality {
        connectionQualities[server.id.uuidString] ?? .unknown
    }

    private func startHealthMonitor(for server: OPCUAServer, client: SimpleOpcUaClient) {
        let serverId = server.id.uuidString
        stopHealthMonitor(for: server)

        let task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self?.healthCheckInterval ?? 6) * 1_000_000_000)
                guard let self else { continue }

                if Task.isCancelled {
                    break
                }

                guard client.connectionStatus else {
                    await self.handleConnectionLoss(for: server, reason: "Connection dropped")
                    break
                }

                let startTime = Date()
                let serviceLevel = await OPCUAClientWork.run {
                    client.readValue(nodeId: "ns=0;i=2257")
                }
                let duration = Date().timeIntervalSince(startTime)

                if serviceLevel == nil {
                    let failures = (self.healthFailureCounts[serverId] ?? 0) + 1
                    self.healthFailureCounts[serverId] = failures
                    self.connectionQualities[serverId] = .poor
                    self.appState?.notifyConnectionStateChanged()
                    NotificationCenter.default.post(name: .opcuaConnectionChanged, object: nil)

                    if failures >= 2 {
                        await self.handleConnectionLoss(for: server, reason: "Health check failed")
                        break
                    }
                } else {
                    self.healthFailureCounts[serverId] = 0
                    let quality = self.qualityForResponseTime(duration)
                    if self.connectionQualities[serverId] != quality {
                        self.connectionQualities[serverId] = quality
                        self.appState?.notifyConnectionStateChanged()
                        NotificationCenter.default.post(name: .opcuaConnectionChanged, object: nil)
                    }
                }
            }
        }

        healthMonitorTasks[serverId] = task
    }

    private func stopHealthMonitor(for server: OPCUAServer) {
        stopHealthMonitor(forId: server.id.uuidString)
    }

    private func stopHealthMonitor(forId serverId: String) {
        if let task = healthMonitorTasks[serverId] {
            task.cancel()
            healthMonitorTasks.removeValue(forKey: serverId)
        }
    }

    private func qualityForResponseTime(_ duration: TimeInterval) -> ConnectionQuality {
        if duration < 0.2 {
            return .excellent
        }
        if duration < 1.0 {
            return .good
        }
        return .poor
    }

    private func handleConnectionLoss(for server: OPCUAServer, reason: String) async {
        let serverId = server.id.uuidString
        stopHealthMonitor(forId: serverId)

        if let client = connectedClients[serverId] {
            await OPCUAClientWork.run {
                client.disconnect()
            }
        }

        await MainActor.run {
            stopNetworkTraceRelay(forId: serverId)
            connectedClients.removeValue(forKey: serverId)
            connectionStatusCache[serverId] = .error
            connectionErrors[serverId] = connectionLossDetail(for: server, reason: reason)
            connectionQualities[serverId] = .poor
            diagnostics.log("Connection lost to \(server.name): \(reason)", level: .warning, component: "Connection")
            appState?.notifyConnectionStateChanged()
            NotificationCenter.default.post(name: .opcuaConnectionChanged, object: nil)
        }

        alarmManager.addAlarm(Alarm(
            message: "Connection lost: \(reason)",
            severity: .high,
            source: server.name
        ))

        alarmManager.logEvent(SystemEvent(
            message: "Connection lost",
            type: .connection,
            source: server.name,
            data: ["reason": reason]
        ))

        scheduleReconnect(for: server)
    }

    private func scheduleReconnect(for server: OPCUAServer) {
        let serverId = server.id.uuidString
        if manualDisconnects.contains(serverId) {
            return
        }
        if reconnectTasks[serverId] != nil {
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let attempt = (self.reconnectAttempts[serverId] ?? 0) + 1
                self.reconnectAttempts[serverId] = attempt

                let delay = min(pow(2.0, Double(attempt - 1)), self.maxReconnectDelay)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                if Task.isCancelled {
                    break
                }

                self.connectionStatusCache[serverId] = .connecting
                self.appState?.notifyConnectionStateChanged()
                NotificationCenter.default.post(name: .opcuaConnectionChanged, object: nil)

                let success = await self.connectToServer(server)
                if success {
                    self.reconnectAttempts[serverId] = 0
                    self.cancelReconnect(for: server)
                    break
                }
            }
        }

        reconnectTasks[serverId] = task
    }

    private func cancelReconnect(for server: OPCUAServer) {
        cancelReconnect(forId: server.id.uuidString)
    }

    private func cancelReconnect(forId serverId: String) {
        if let task = reconnectTasks[serverId] {
            task.cancel()
            reconnectTasks.removeValue(forKey: serverId)
        }
        reconnectAttempts.removeValue(forKey: serverId)
    }
    
    // MARK: - Browse Operations

    private func connectedClient(for server: OPCUAServer, operation: String, component: String) -> SimpleOpcUaClient? {
        let serverId = server.id.uuidString

        guard let client = connectedClients[serverId], client.connectionStatus else {
            let message = "Cannot \(operation): no OPC UA server connected for \(server.name)"
            diagnostics.log(message, level: .warning, component: component)
            diagnostics.recordMessageError()

            if connectedClients[serverId] != nil {
                connectionStatusCache[serverId] = .error
                connectionErrors[serverId] = connectionLossDetail(for: server, reason: "Session is not connected")
                connectionQualities[serverId] = .poor
            } else if connectionStatusCache[serverId] == nil {
                connectionStatusCache[serverId] = .disconnected
            }

            appState?.notifyConnectionStateChanged()
            NotificationCenter.default.post(name: .opcuaConnectionChanged, object: nil)
            return nil
        }

        return client
    }

    func browseAddressSpace(for server: OPCUAServer, nodeId: String = "ns=0;i=85", maxDepth: Int = 1) async -> [NodeInfo] {
        print("🎬 BROWSE: Starting browse operation for server: \(server.name)")

        guard let client = connectedClient(for: server, operation: "browse address space", component: "Browser") else {
            print("❌ BROWSE: Client not found for server \(server.name)")
            return []
        }

        diagnostics.log("Browsing node \(nodeId) on \(server.name) with maxDepth \(maxDepth)", level: .debug, component: "Browser")
        recordProtocolEvent(type: "MSG", direction: .sent, size: 64, serverId: server.id.uuidString)

        // Browse root folder first
        let rootNodes = await OPCUAClientWork.run {
            client.browseRootFolder()
        }
        print("📁 BROWSE: Found \(rootNodes.count) root nodes")

        recordProtocolEvent(type: "MSG", direction: .received, size: 128 + rootNodes.count * 48, serverId: server.id.uuidString)

        // Recursively browse each node to build the full tree
        var nodeInfos: [NodeInfo] = []
        for opcuaNode in rootNodes {
            let children = await browseNodeRecursively(client: client, nodeId: opcuaNode.nodeId, currentDepth: 1, maxDepth: maxDepth)

            // Read initial value and data type for Variable nodes
            var initialValue: String? = nil
            var dataType: String? = nil
            if opcuaNode.nodeClass == "Variable" {
                initialValue = await OPCUAClientWork.run {
                    client.readValue(nodeId: opcuaNode.nodeId)
                }
                dataType = await OPCUAClientWork.run {
                    client.readDataType(nodeId: opcuaNode.nodeId)
                } ?? "Unknown"
            }

            nodeInfos.append(NodeInfo(
                nodeId: opcuaNode.nodeId,
                displayName: opcuaNode.displayName,
                nodeClass: convertStringToNodeClass(opcuaNode.nodeClass),
                dataType: dataType,
                value: initialValue,
                timestamp: initialValue != nil ? Date() : nil,
                quality: initialValue != nil ? .good : .uncertain,
                children: children.isEmpty ? nil : children
            ))
        }

        diagnostics.log("Browse completed with \(nodeInfos.count) nodes", level: .debug, component: "Browser")
        return nodeInfos
    }

    func browseChildNodes(for server: OPCUAServer, parentNodeId: String) async -> [NodeInfo] {
        guard let client = connectedClient(for: server, operation: "browse child nodes", component: "Browser") else {
            print("❌ BROWSE: No connection for server \(server.name)")
            return []
        }
        
        let childNodes = await OPCUAClientWork.run {
            client.browseNode(nodeId: parentNodeId)
        }
        
        if childNodes.isEmpty {
            print("📂 BROWSE: Node \(parentNodeId) has no children")
            return []
        }
        
        print("📂 BROWSE: Node \(parentNodeId) has \(childNodes.count) children")
        
        return childNodes.map { opcuaNode -> NodeInfo in
            return NodeInfo(
                nodeId: opcuaNode.nodeId,
                displayName: opcuaNode.displayName,
                nodeClass: convertStringToNodeClass(opcuaNode.nodeClass),
                dataType: nil,
                value: nil,
                timestamp: nil,
                quality: .uncertain,
                children: nil  // Don't recursively load children
            )
        }
    }
    
    private func browseNodeRecursively(client: SimpleOpcUaClient, nodeId: String, currentDepth: Int, maxDepth: Int) async -> [NodeInfo] {
        // Stop if we've reached max depth
        guard currentDepth < maxDepth else {
            return []
        }

        let childNodes = await OPCUAClientWork.run {
            client.browseNode(nodeId: nodeId)
        }

        if childNodes.isEmpty {
            return []
        }

        print("📂 BROWSE: Node \(nodeId) has \(childNodes.count) children at depth \(currentDepth)")

        var nodeInfos: [NodeInfo] = []
        for opcuaNode in childNodes {
            // Only recurse into Object nodes (not Variables)
            var children: [NodeInfo]? = nil
            if opcuaNode.nodeClass == "Object" {
                let subChildren = await browseNodeRecursively(client: client, nodeId: opcuaNode.nodeId, currentDepth: currentDepth + 1, maxDepth: maxDepth)
                children = subChildren.isEmpty ? nil : subChildren
            }

            // Read initial value and data type for Variable nodes
            var initialValue: String? = nil
            var dataType: String? = nil
            if opcuaNode.nodeClass == "Variable" {
                initialValue = await OPCUAClientWork.run {
                    client.readValue(nodeId: opcuaNode.nodeId)
                }
                dataType = await OPCUAClientWork.run {
                    client.readDataType(nodeId: opcuaNode.nodeId)
                } ?? "Unknown"
            }

            nodeInfos.append(NodeInfo(
                nodeId: opcuaNode.nodeId,
                displayName: opcuaNode.displayName,
                nodeClass: convertStringToNodeClass(opcuaNode.nodeClass),
                dataType: dataType,
                value: initialValue,
                timestamp: initialValue != nil ? Date() : nil,
                quality: initialValue != nil ? .good : .uncertain,
                children: children
            ))
        }

        return nodeInfos
    }
    
    private func convertStringToNodeClass(_ nodeClass: String) -> NodeInfo.NodeClass {
        switch nodeClass.lowercased() {
        case "object": return .object
        case "variable": return .variable
        case "method": return .method
        case "objecttype": return .objectType
        case "variabletype": return .variableType
        case "referencetype": return .referenceType
        case "datatype": return .dataType
        case "view": return .view
        default: return .object // Default to object for unknown types
        }
    }
    
    // MARK: - Read/Write Operations

    func readNodeValue(for server: OPCUAServer, nodeId: String) async -> String? {
        guard let client = connectedClient(for: server, operation: "read node value", component: "Read") else {
            return nil
        }
        return await OPCUAClientWork.run {
            client.readValue(nodeId: nodeId)
        }
    }

    /// Alias for readNodeValue - used by AnalyticsManager
    func readValue(for server: OPCUAServer, nodeId: String) async -> String? {
        return await readNodeValue(for: server, nodeId: nodeId)
    }
    
    func writeNodeValue(
        for server: OPCUAServer,
        nodeId: String,
        value: String,
        dataType: String?,
        nodeDisplayName: String? = nil
    ) async -> Bool {
        guard let client = connectedClient(for: server, operation: "write node value", component: "Write") else {
            appState?.writeHistory.addEntry(
                server: server,
                nodeId: nodeId,
                nodeDisplayName: nodeDisplayName,
                value: value,
                dataType: dataType,
                success: false,
                errorMessage: "No OPC UA server connected."
            )
            return false
        }
        
        let success = await OPCUAClientWork.run {
            client.writeValue(nodeId: nodeId, value: value, dataType: dataType)
        }
        if success {
            diagnostics.log("Wrote value for node \(nodeId) on \(server.name)", level: .info, component: "Write")
            recordProtocolEvent(type: "WRITE", direction: .sent, size: 32, serverId: server.id.uuidString)
        } else {
            diagnostics.log("Failed to write value for node \(nodeId) on \(server.name)", level: .error, component: "Write")
            diagnostics.recordMessageError()
        }
        appState?.writeHistory.addEntry(
            server: server,
            nodeId: nodeId,
            nodeDisplayName: nodeDisplayName,
            value: value,
            dataType: dataType,
            success: success,
            errorMessage: success ? nil : "Write failed. Check value and connection."
        )
        return success
    }
    
    // MARK: - Subscription Management
    
    func createSubscription(for server: OPCUAServer, publishingInterval: Double = 1000.0) async -> Bool {
        guard let client = connectedClient(for: server, operation: "create subscription", component: "Subscription") else {
            return false
        }
        
        // Create subscription if it doesn't exist
        if client.subscriptionId == nil {
            let success = await OPCUAClientWork.run {
                client.createSubscription(publishingInterval: publishingInterval)
            }
            if success {
                diagnostics.log("Created subscription for \(server.name) with interval \(publishingInterval)ms", level: .info, component: "Subscription")
                alarmManager.logEvent(SystemEvent(
                    message: "Subscription created",
                    type: .subscription,
                    source: server.name,
                    data: ["interval": "\(publishingInterval)"]
                ))
                return true
            } else {
                diagnostics.log("Failed to create subscription for \(server.name)", level: .error, component: "Subscription")
                return false
            }
        }
        
        return true // Already has subscription
    }
    
    func addMonitoredItem(for server: OPCUAServer, nodeId: String, samplingInterval: Double = 1000.0) async -> Bool {
        guard let client = connectedClient(for: server, operation: "add monitored item", component: "Subscription") else {
            return false
        }
        
        // Ensure subscription exists first
        if client.subscriptionId == nil {
            let created = await createSubscription(for: server)
            if !created {
                return false
            }
        }
        
        // Add monitored item with data change callback
        let success = await OPCUAClientWork.run {
            client.addMonitoredItem(
                nodeId: nodeId,
                samplingInterval: samplingInterval
            ) { [weak self] value, timestamp in
                // Handle data change notification
                Task { @MainActor in
                    self?.handleDataChange(serverId: server.id.uuidString, nodeId: nodeId, value: value)
                }
            }
        }
        
        if success {
            diagnostics.log("Added monitored item for node \(nodeId) on \(server.name)", level: .info, component: "Subscription")
            alarmManager.logEvent(SystemEvent(
                message: "Monitored item added",
                type: .subscription,
                source: server.name,
                data: ["nodeId": nodeId, "samplingInterval": "\(samplingInterval)"]
            ))

            if let value = await readValue(for: server, nodeId: nodeId) {
                handleDataChange(serverId: server.id.uuidString, nodeId: nodeId, value: value)
            }
        } else {
            diagnostics.log("Failed to add monitored item for node \(nodeId) on \(server.name)", level: .error, component: "Subscription")
        }
        
        return success
    }
    
    func removeMonitoredItem(for server: OPCUAServer, nodeId: String) async -> Bool {
        guard let client = connectedClient(for: server, operation: "remove monitored item", component: "Subscription") else {
            return false
        }
        
        let success = await OPCUAClientWork.run {
            client.removeMonitoredItem(nodeId: nodeId)
        }
        if success {
            diagnostics.log("Removed monitored item for node \(nodeId) on \(server.name)", level: .info, component: "Subscription")
            alarmManager.logEvent(SystemEvent(
                message: "Monitored item removed",
                type: .subscription,
                source: server.name,
                data: ["nodeId": nodeId]
            ))
        }
        return success
    }
    
    /// Restores all active subscriptions and their monitored items for a given server.
    /// This is called automatically after a successful connection.
    func restoreSubscriptions(for server: OPCUAServer) async {
        guard let appState = appState else {
            diagnostics.log("Cannot restore subscriptions: AppState is nil", level: .warning, component: "Subscription")
            return
        }
        
        // Find all active subscriptions for this server
        let serverSubscriptions = appState.subscriptions.filter { $0.serverId == server.id && $0.isActive }
        
        if serverSubscriptions.isEmpty {
            diagnostics.log("No active subscriptions to restore for \(server.name)", level: .debug, component: "Subscription")
            return
        }
        
        diagnostics.log("Restoring \(serverSubscriptions.count) subscriptions for \(server.name)", level: .info, component: "Subscription")
        print("🔄 [ConnectionManager] Restoring \(serverSubscriptions.count) subscriptions for \(server.name)")
        
        // Validate subscriptions before restoring
        guard let client = connectedClients[server.id.uuidString] else {
            diagnostics.log("No client available for validation", level: .warning, component: "Subscription")
            return
        }
        
        var validationIssues: [MonitoredItemValidation] = []
        
        for subscription in serverSubscriptions {
            // Validate all items in this subscription first
            print("🔍 [ConnectionManager] Validating subscription '\(subscription.name)'...")
            let validations = await OPCUAClientWork.run {
                SubscriptionValidator.validateSubscription(subscription, client: client)
            }
            
            // Check for critical issues
            let criticalIssues = validations.filter { 
                $0.issue?.severity == .critical || $0.issue == .displayNameMismatch 
            }
            
            if !criticalIssues.isEmpty {
                print("⚠️ [ConnectionManager] Validation issues found in subscription '\(subscription.name)':")
                for issue in criticalIssues {
                    if let issueDesc = issue.issue {
                        print("   ❌ Node \(issue.nodeId): \(issueDesc.description)")
                        print("      Saved: '\(issue.savedDisplayName)' → Server: '\(issue.serverDisplayName ?? "N/A")'")
                        
                        // Log to diagnostics for user visibility
                        diagnostics.log(
                            "Subscription validation failed for \(issue.nodeId): \(issueDesc.description) - Display name mismatch: expected '\(issue.savedDisplayName)', got '\(issue.serverDisplayName ?? "unknown")'",
                            level: .error,
                            component: "Subscription"
                        )
                        
                        // Add to validation issues for reporting
                        validationIssues.append(issue)
                    }
                }
                
                // Notify user through alarm system
                alarmManager.addAlarm(Alarm(
                    message: "Subscription '\(subscription.name)' has validation errors - nodes may have changed on server",
                    severity: .high,
                    source: server.name
                ))
                
                // Skip items with critical issues
                continue
            }
            
            // 1. Create the subscription on the server
            let created = await createSubscription(for: server, publishingInterval: subscription.publishingInterval)
            
            if created {
                diagnostics.log("Created/Found subscription '\(subscription.name)' (\(subscription.id))", level: .debug, component: "Subscription")
                print("✅ [ConnectionManager] Subscription '\(subscription.name)' ready")
                
                // 2. Add all monitored items in this subscription
                var successCount = 0
                for item in subscription.monitoredItems {
                    // Skip items with validation issues
                    if let validation = validations.first(where: { $0.nodeId == item.nodeId }),
                       !validation.isValid {
                        print("⚠️ [ConnectionManager] Skipping invalid item: \(item.displayName) (\(item.nodeId))")
                        continue
                    }
                    
                    print("📡 [ConnectionManager] Restoring item: \(item.displayName) (\(item.nodeId))")
                    
                    let success = await addMonitoredItem(
                        for: server, 
                        nodeId: item.nodeId, 
                        samplingInterval: item.samplingInterval
                    )
                    
                    if success {
                        successCount += 1

                        // Read initial value to populate UI immediately
                        if let value = await readValue(for: server, nodeId: item.nodeId) {
                            handleDataChange(serverId: server.id.uuidString, nodeId: item.nodeId, value: value)
                        } else {
                            // Value is NULL or not ready yet - subscription will fill it in
                            handleDataChange(serverId: server.id.uuidString, nodeId: item.nodeId, value: "")
                        }
                    } else {
                        diagnostics.log("Failed to restore monitored item \(item.nodeId) for \(server.name)", level: .error, component: "Subscription")
                        print("❌ [ConnectionManager] Failed to monitor item \(item.nodeId)")
                    }
                    
                    // Small delay to avoid hammering the server
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                }
                
                diagnostics.log("Restored \(successCount)/\(subscription.monitoredItems.count) items for subscription '\(subscription.name)'", level: .info, component: "Subscription")
                print("🎊 [ConnectionManager] Restored \(successCount)/\(subscription.monitoredItems.count) items for '\(subscription.name)'")
            } else {
                diagnostics.log("Failed to restore subscription '\(subscription.name)' for \(server.name)", level: .error, component: "Subscription")
                print("❌ [ConnectionManager] Failed to create subscription '\(subscription.name)'")
            }
        }
        
        // If there were validation issues, generate a report
        if !validationIssues.isEmpty {
            let report = SubscriptionValidator.generateValidationReport(validations: validationIssues)
            print("\n" + report)
            
            // Store the validation issues for UI display
            Task { @MainActor in
                self.appState?.lastSubscriptionValidationIssues = validationIssues
                
                // Show alert to user
                NotificationCenter.default.post(
                    name: .subscriptionValidationFailed,
                    object: nil,
                    userInfo: ["issues": validationIssues, "server": server.name]
                )
            }
        }
    }

    /// Reads all persisted monitored items for a connected server and updates the UI cache.
    /// This keeps subscription cards from showing stale persisted values after the server
    /// process or Modbus simulator has been restarted.
    func refreshMonitoredItems(for server: OPCUAServer) async {
        guard let client = connectedClient(for: server, operation: "refresh monitored item values", component: "Subscription") else {
            return
        }

        guard let appState else {
            diagnostics.log("Cannot refresh monitored items: AppState is nil", level: .warning, component: "Subscription")
            return
        }

        let items = appState.subscriptions
            .filter { $0.serverId == server.id && $0.isActive }
            .flatMap { $0.monitoredItems }

        guard !items.isEmpty else {
            return
        }

        diagnostics.log("Refreshing \(items.count) monitored item values for \(server.name)", level: .debug, component: "Subscription")

        var failureCount = 0
        for item in items {
            let value = await OPCUAClientWork.run {
                client.readValue(nodeId: item.nodeId)
            }
            if let value {
                handleDataChange(serverId: server.id.uuidString, nodeId: item.nodeId, value: value)
            } else {
                failureCount += 1
                appState.updateMonitoredItemValue(
                    nodeId: item.nodeId,
                    value: "",
                    quality: .uncertain
                )
            }

            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        if failureCount == items.count {
            await handleConnectionLoss(for: server, reason: "Could not refresh monitored item values")
        } else if failureCount > 0 {
            diagnostics.log("Refreshed monitored items for \(server.name) with \(failureCount) read failures", level: .warning, component: "Subscription")
        }
    }

    func refreshAllConnectedMonitoredItems() async {
        guard let appState else { return }

        for server in appState.servers where isConnected(to: server) {
            await refreshMonitoredItems(for: server)
        }
    }
    
    // MARK: - Data Change Handling
    
    @Published var liveDataValues: [String: (value: String, timestamp: Date)] = [:]
    
    private func handleDataChange(serverId: String, nodeId: String, value: String) {
        let timestamp = Date()

        guard shouldEmitValue(nodeId: nodeId, newValue: value) else {
            return
        }

        if shouldLogDataChange(nodeId: nodeId, timestamp: timestamp) {
            let sourceName = appState?.servers.first { $0.id.uuidString == serverId }?.name ?? serverId
            // Log the fact of a change without embedding the value. Sensor values
            // are runtime data; the Events log is in-memory but visible in the UI
            // and shouldn't surface readings to anyone glancing at the screen.
            alarmManager.logEvent(SystemEvent(
                message: "Data change for \(nodeId)",
                type: .dataChange,
                source: sourceName,
                data: ["nodeId": nodeId]
            ))
        }

        // Update live data store
        liveDataValues[nodeId] = (value: value, timestamp: timestamp)

        // Update monitored items in AppState (for UI updates)
        Task { @MainActor in
            // Update the monitored item value through appState
            self.appState?.updateMonitoredItemValue(
                nodeId: nodeId,
                value: value,
                quality: .good
            )
        }

        // Notify other parts of the app
        NotificationCenter.default.post(
            name: .opcuaDataChanged,
            object: nil,
            userInfo: [
                "serverId": serverId,
                "nodeId": nodeId,
                "value": value,
                "timestamp": timestamp
            ]
        )
    }

    private func shouldEmitValue(nodeId: String, newValue: String) -> Bool {
        guard let appState else { return true }

        let monitoredItem = appState.subscriptions
            .flatMap { $0.monitoredItems }
            .first { $0.nodeId == nodeId }

        guard let monitoredItem else { return true }
        guard monitoredItem.deadbandType != .none else { return true }
        guard monitoredItem.deadbandValue > 0 else { return true }

        let previousValue = liveDataValues[nodeId]?.value
        guard let previousValue else { return true }

        guard let previousNumber = Double(previousValue),
              let newNumber = Double(newValue) else {
            return true
        }

        let delta = abs(newNumber - previousNumber)

        switch monitoredItem.deadbandType {
        case .absolute:
            return delta >= monitoredItem.deadbandValue
        case .percent:
            let base = abs(previousNumber)
            if base == 0 {
                return delta >= monitoredItem.deadbandValue
            }
            let percent = (delta / base) * 100.0
            return percent >= monitoredItem.deadbandValue
        case .none:
            return true
        }
    }

    private func shouldLogDataChange(nodeId: String, timestamp: Date) -> Bool {
        if let last = lastEventLogByNode[nodeId],
           timestamp.timeIntervalSince(last) < dataChangeLogInterval {
            return false
        }
        lastEventLogByNode[nodeId] = timestamp
        return true
    }
    
    // MARK: - Live Data Access
    
    func getLiveValue(for nodeId: String) -> String? {
        return liveDataValues[nodeId]?.value
    }
    
    func getLastUpdate(for nodeId: String) -> Date? {
        return liveDataValues[nodeId]?.timestamp
    }
    
    // MARK: - Status Helpers
    
    func isConnected(to server: OPCUAServer) -> Bool {
        return connectionStatusCache[server.id.uuidString] == .connected
    }
    
    func getConnectionStatus(for server: OPCUAServer) -> ConnectionStatus {
        // Use cached status to avoid accessing @Published properties
        return connectionStatusCache[server.id.uuidString] ?? .disconnected
    }
    
    func getLastError(for server: OPCUAServer) -> ConnectionErrorDetail? {
        return connectionErrors[server.id.uuidString]
    }

    private func defaultConnectionFailureDetail(for server: OPCUAServer, endpoint: String) -> ConnectionErrorDetail {
        var hints: [String] = [
            "Verify the server is running and reachable",
            "Confirm the endpoint and port are correct"
        ]

        if server.authenticationMode == .usernamePassword {
            hints.append("Verify the username and password")
        }
        if server.authenticationMode == .certificate || server.securityMode != .none {
            hints.append("Check security policy and certificate paths")
        }

        return ConnectionErrorDetail(
            message: "Unable to connect to \(endpoint).",
            hints: Array(hints.prefix(3)),
            actions: [.retryConnection, .editServer]
        )
    }

    private func connectionLossDetail(for server: OPCUAServer, reason: String) -> ConnectionErrorDetail {
        return ConnectionErrorDetail(
            message: "Connection lost: \(reason).",
            hints: [
                "Check server availability and network connectivity",
                "Wait for auto-reconnect or retry manually"
            ],
            actions: [.retryConnection, .editServer]
        )
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let opcuaDataChanged = Notification.Name("OPCUADataChanged")
    static let opcuaConnectionChanged = Notification.Name("OPCUAConnectionChanged")
    static let subscriptionValidationFailed = Notification.Name("SubscriptionValidationFailed")
}
