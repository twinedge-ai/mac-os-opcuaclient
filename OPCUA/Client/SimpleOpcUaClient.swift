import Foundation

nonisolated enum OPCUAClientWork {
    static func run<T>(_ operation: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: operation())
            }
        }
    }
}

private struct ClientSecurityPreferences {
    let requireEncryption: Bool
    let minSecurityLevel: String

    static var current: ClientSecurityPreferences {
        let defaults = UserDefaults.standard
        return ClientSecurityPreferences(
            requireEncryption: defaults.object(forKey: "requireEncryption") as? Bool ?? true,
            minSecurityLevel: defaults.string(forKey: "minSecurityLevel") ?? "sign"
        )
    }

    var minimumMode: SecurityMode {
        switch minSecurityLevel {
        case "none":
            return .none
        case "signAndEncrypt":
            return .signAndEncrypt
        default:
            return .sign
        }
    }
}

// MARK: - Simple OPC UA Client using C wrapper
class SimpleOpcUaClient {
    private var clientPtr: OpaquePointer?
    private var isConnected = false
    private(set) var lastErrorDetail: ConnectionErrorDetail?
    
    // Lock for thread safety
    private let lock = NSRecursiveLock()
    
    init() {
        clientPtr = opcua_client_create()
    }
    
    deinit {
        // Stop background processing first
        stopSubscriptionProcessing()
        lock.lock()
        defer { lock.unlock() }
        if let ptr = clientPtr {
            opcua_client_destroy(ptr)
        }
    }
    
    // MARK: - Connection Management
    
    func connect(to endpoint: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let ptr = clientPtr else { return false }

        lastErrorDetail = nil

        let result = endpoint.withCString { endpointPtr in
            return opcua_client_connect(ptr, endpointPtr)
        }

        isConnected = result

        if isConnected {
            startSubscriptionProcessing()
        } else {
            lastErrorDetail = ConnectionErrorDetail(
                message: "Unable to connect to \(endpoint).",
                hints: ["Verify the server is running and reachable"],
                actions: [.retryConnection, .editServer]
            )
        }

        return isConnected
    }

    func connect(to endpoint: String, server: OPCUAServer) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let ptr = clientPtr else { return false }

        lastErrorDetail = nil
        if let validationError = validateConnectionSettings(endpoint: endpoint, server: server) {
            lastErrorDetail = validationError
            return false
        }

        let securityConfigured = configureSecurityIfNeeded(for: server)
        if !securityConfigured {
            if lastErrorDetail == nil {
                lastErrorDetail = ConnectionErrorDetail(
                    message: "Failed to configure security settings.",
                    hints: [
                        "Verify the security policy and mode",
                        "Check certificate and key paths"
                    ],
                    actions: [.editServer]
                )
            }
            return false
        }

        let connected: Bool
        switch server.authenticationMode {
        case .usernamePassword:
            guard let username = server.username, let password = server.password else {
                return false
            }
            connected = endpoint.withCString { endpointPtr in
                return username.withCString { userPtr in
                    return password.withCString { passPtr in
                        opcua_client_connect_username(ptr, endpointPtr, userPtr, passPtr)
                    }
                }
            }
        case .anonymous, .certificate:
            connected = endpoint.withCString { endpointPtr in
                return opcua_client_connect(ptr, endpointPtr)
            }
        }

        isConnected = connected

        if isConnected {
            startSubscriptionProcessing()
        } else if lastErrorDetail == nil {
            lastErrorDetail = makeGenericConnectionFailure(endpoint: endpoint, server: server)
        }

        return isConnected
    }

    func disconnect() {
        lock.lock()
        defer { lock.unlock() }

        guard let ptr = clientPtr, isConnected else { return }

        stopSubscriptionProcessing()
        opcua_client_disconnect(ptr)
        isConnected = false
    }

    private func configureSecurityIfNeeded(for server: OPCUAServer) -> Bool {
        // Called within lock of connect()
        guard let ptr = clientPtr else { return false }

        let usesSecurity = server.securityMode != .none && server.securityPolicy != .none
        let requiresCerts = usesSecurity || server.authenticationMode == .certificate

        if !requiresCerts {
            return "None".withCString { policyPtr in
                opcua_client_configure_security(ptr, policyPtr, mapSecurityMode(.none), nil, nil, nil)
            }
        }

        if server.authenticationMode == .certificate && !usesSecurity {
            lastErrorDetail = ConnectionErrorDetail(
                message: "Certificate authentication requires a security policy and mode.",
                hints: [
                    "Select a security policy and mode supported by the server",
                    "Switch authentication to Anonymous or Username/Password"
                ],
                actions: [.editServer]
            )
            return false
        }

        guard let certPath = server.certificatePath,
              let keyPath = server.privateKeyPath else {
            lastErrorDetail = ConnectionErrorDetail(
                message: "Client certificate and private key are required for secure connections.",
                hints: [
                    "Select client certificate and key files",
                    "Switch security mode to None for anonymous access"
                ],
                actions: [.editServer]
            )
            return false
        }

        // A server certificate is required for Sign / Sign&Encrypt so that the
        // open62541 trust list can verify the server identity. Without it the
        // session is vulnerable to MITM regardless of the security policy. We
        // refuse to fall back to "any server" trust silently.
        guard let serverCertPathRaw = server.serverCertificatePath,
              !serverCertPathRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastErrorDetail = ConnectionErrorDetail(
                message: "Server certificate is required when Sign or Sign & Encrypt is selected.",
                hints: [
                    "Select the server's certificate to pin trust",
                    "Use Discovery to fetch the server's certificate first"
                ],
                actions: [.editServer]
            )
            return false
        }

        let securityModeValue = mapSecurityMode(server.securityMode)
        let fileManager = FileManager.default
        let resolvedCertPath = (certPath as NSString).expandingTildeInPath
        let resolvedKeyPath = (keyPath as NSString).expandingTildeInPath
        let resolvedServerCertPath = (serverCertPathRaw as NSString).expandingTildeInPath

        return ServerSecurityFileStore.withAccess(
            serverId: server.id,
            role: .clientCertificate,
            fallbackPath: resolvedCertPath
        ) { accessibleCertPath in
            ServerSecurityFileStore.withAccess(
                serverId: server.id,
                role: .privateKey,
                fallbackPath: resolvedKeyPath
            ) { accessibleKeyPath in
                ServerSecurityFileStore.withAccess(
                    serverId: server.id,
                    role: .serverCertificate,
                    fallbackPath: resolvedServerCertPath
                ) { accessibleServerCertPath in
                    guard fileManager.fileExists(atPath: accessibleCertPath) else {
                        lastErrorDetail = ConnectionErrorDetail(
                            message: "Certificate file not found at \(accessibleCertPath)",
                            hints: ["Check the file path in settings"],
                            actions: [.editServer]
                        )
                        return false
                    }

                    guard fileManager.fileExists(atPath: accessibleKeyPath) else {
                        lastErrorDetail = ConnectionErrorDetail(
                            message: "Private key file not found at \(accessibleKeyPath)",
                            hints: ["Check the file path in settings"],
                            actions: [.editServer]
                        )
                        return false
                    }

                    guard fileManager.fileExists(atPath: accessibleServerCertPath) else {
                        lastErrorDetail = ConnectionErrorDetail(
                            message: "Server certificate not found at \(accessibleServerCertPath).",
                            hints: [
                                "Verify the server certificate path",
                                "Fetch the certificate from the server with Discovery"
                            ],
                            actions: [.editServer]
                        )
                        return false
                    }

                    let securityPolicyName = server.securityPolicy.rawValue
                    let securityConfigured = securityPolicyName.withCString { policyPtr in
                        accessibleCertPath.withCString { certPtr in
                            accessibleKeyPath.withCString { keyPtr in
                                accessibleServerCertPath.withCString { serverCertPtr in
                                    opcua_client_configure_security(
                                        ptr,
                                        policyPtr,
                                        securityModeValue,
                                        certPtr,
                                        keyPtr,
                                        serverCertPtr
                                    )
                                }
                            }
                        }
                    }

                    guard securityConfigured else {
                        return false
                    }

                    guard server.authenticationMode == .certificate else {
                        return true
                    }

                    let authConfigured = accessibleCertPath.withCString { certPtr in
                        accessibleKeyPath.withCString { keyPtr in
                            opcua_client_configure_certificate_auth(ptr, certPtr, keyPtr)
                        }
                    }

                    if !authConfigured {
                        lastErrorDetail = ConnectionErrorDetail(
                            message: "Failed to configure certificate user authentication.",
                            hints: [
                                "Verify the client certificate and private key are readable",
                                "Ensure open62541 was built with X509 authentication support"
                            ],
                            actions: [.editServer]
                        )
                    }

                    return authConfigured
                }
            }
        }
    }
    
    private func validateConnectionSettings(endpoint: String, server: OPCUAServer) -> ConnectionErrorDetail? {
        if server.networkSchema != .opcTcp {
            return ConnectionErrorDetail(
                message: "Only opc.tcp endpoints are supported by this build.",
                hints: [
                    "Use an opc.tcp endpoint",
                    "Remove OPC WebSocket profiles until WSS transport support is added"
                ],
                actions: [.editServer]
            )
        }

        let trimmedHost = server.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedHost.isEmpty {
            return ConnectionErrorDetail(
                message: "Host is required to connect.",
                hints: ["Enter a host name or IP address"],
                actions: [.editServer]
            )
        }

        if server.port <= 0 {
            return ConnectionErrorDetail(
                message: "Port must be a positive number.",
                hints: ["Use the server's OPC UA port (default 4840)"],
                actions: [.editServer]
            )
        }

        let securityPreferences = ClientSecurityPreferences.current
        if securityPreferences.requireEncryption && server.securityMode != .signAndEncrypt {
            return ConnectionErrorDetail(
                message: "Global security settings require Sign & Encrypt.",
                hints: [
                    "Select Sign & Encrypt for this server",
                    "Change Security settings only for intentional test connections"
                ],
                actions: [.editServer]
            )
        }

        if securityModeRank(server.securityMode) < securityModeRank(securityPreferences.minimumMode) {
            return ConnectionErrorDetail(
                message: "Server security mode is below the configured minimum.",
                hints: [
                    "Raise the server profile security mode",
                    "Lower the minimum only for isolated test systems"
                ],
                actions: [.editServer]
            )
        }

        if server.securityMode != .none && server.trustBehavior != .blockUnknown {
            return ConnectionErrorDetail(
                message: "Only pinned server-certificate trust is supported.",
                hints: [
                    "Set Trust Behavior to Block Unknown Certificates",
                    "Select the server certificate for this profile"
                ],
                actions: [.editServer]
            )
        }

        if let url = URL(string: endpoint) {
            let scheme = url.scheme ?? ""
            if !scheme.hasPrefix("opc") || url.host == nil {
                return ConnectionErrorDetail(
                    message: "Endpoint format is invalid.",
                    hints: ["Use the format opc.tcp://host:port"],
                    actions: [.editServer]
                )
            }
        } else {
            return ConnectionErrorDetail(
                message: "Endpoint format is invalid.",
                hints: ["Use the format opc.tcp://host:port"],
                actions: [.editServer]
            )
        }

        if server.authenticationMode == .usernamePassword {
            let user = server.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let pass = server.password?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if user.isEmpty || pass.isEmpty {
                return ConnectionErrorDetail(
                    message: "Username and password are required.",
                    hints: [
                        "Enter credentials in Authentication",
                        "Switch authentication to Anonymous"
                    ],
                    actions: [.editServer]
                )
            }

            if server.securityMode != .signAndEncrypt || server.securityPolicy == .none {
                return ConnectionErrorDetail(
                    message: "Username/password authentication requires Sign & Encrypt.",
                    hints: [
                        "Select Sign & Encrypt with a non-None security policy",
                        "Use Anonymous only for intentionally unsecured test servers"
                    ],
                    actions: [.editServer]
                )
            }
        }

        if server.securityMode != .none && server.securityPolicy == .none {
            return ConnectionErrorDetail(
                message: "Security mode requires a security policy.",
                hints: [
                    "Select a policy supported by the server",
                    "Use Discovery to check available policies"
                ],
                actions: [.editServer]
            )
        }

        if server.securityMode == .none && server.securityPolicy != .none {
            return ConnectionErrorDetail(
                message: "Security policy selected without a security mode.",
                hints: ["Select Sign or Sign & Encrypt for this policy"],
                actions: [.editServer]
            )
        }

        return nil
    }

    private func securityModeRank(_ mode: SecurityMode) -> Int {
        switch mode {
        case .none:
            return 0
        case .sign:
            return 1
        case .signAndEncrypt:
            return 2
        }
    }

    private func makeGenericConnectionFailure(endpoint: String, server: OPCUAServer) -> ConnectionErrorDetail {
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

    private func mapSecurityMode(_ mode: SecurityMode) -> Int32 {
        switch mode {
        case .none: return 1
        case .sign: return 2
        case .signAndEncrypt: return 3
        }
    }
    
    // MARK: - Browse Operations
    
    func browseRootFolder() -> [SimpleOPCUANode] {
        lock.lock()
        defer { lock.unlock() }
        
        guard let ptr = clientPtr, isConnected else {
            print("❌ Not connected to server")
            return []
        }

        print("📁 Browsing root folder...")

        guard let nodeList = opcua_browse_root(ptr) else {
            print("📄 No nodes found in root folder")
            return []
        }

        defer { opcua_node_list_destroy(nodeList) }

        return parseNodeList(nodeList)
    }

    func browseNode(nodeId: String) -> [SimpleOPCUANode] {
        lock.lock()
        defer { lock.unlock() }
        
        guard let ptr = clientPtr, isConnected else {
            print("❌ Not connected to server")
            return []
        }

        print("📁 Browsing node: \(nodeId)")

        guard let nodeList = nodeId.withCString({ opcua_browse_node(ptr, $0) }) else {
            print("📄 No children found for node: \(nodeId)")
            return []
        }

        defer { opcua_node_list_destroy(nodeList) }

        return parseNodeList(nodeList)
    }

    private func parseNodeList(_ nodeList: OpaquePointer) -> [SimpleOPCUANode] {
        // Called within lock
        let nodeCount = opcua_node_list_count(nodeList)
        var result: [SimpleOPCUANode] = []

        for i in 0..<Int(nodeCount) {
            let nodeId = opcua_node_get_id(nodeList, Int32(i)).map { String(cString: $0) } ?? ""
            let name = opcua_node_get_name(nodeList, Int32(i)).map { String(cString: $0) } ?? ""
            let displayName = opcua_node_get_display_name(nodeList, Int32(i)).map { String(cString: $0) } ?? ""
            let nodeClass = opcua_node_get_class(nodeList, Int32(i)).map { String(cString: $0) } ?? ""

            let node = SimpleOPCUANode(
                nodeId: nodeId,
                browseName: name,
                displayName: displayName,
                nodeClass: nodeClass,
                value: nil,
                dataType: nil
            )

            result.append(node)
            // Excessive logging removed
        }

        return result
    }
    
    // MARK: - Read Operations
    
    func readDoubleValue(nodeId: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let ptr = clientPtr, isConnected else { return nil }
        
        var value: Double = 0.0
        let success = nodeId.withCString { nodeIdPtr in
            return opcua_read_value_double(ptr, nodeIdPtr, &value)
        }
        
        return success != 0 ? value : nil
    }
    
    func readValue(nodeId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard let ptr = clientPtr, isConnected else { return nil }

        guard let cString = nodeId.withCString({ opcua_read_value_string(ptr, $0) }) else {
            // NULL return means value couldn't be read or converted.
            // Subscription updates will fill it in if the node later produces a value.
            return nil
        }

        let value = String(cString: cString)
        opcua_free_string(cString)
        return value
    }

    func readDataType(nodeId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard let ptr = clientPtr, isConnected else { return nil }

        guard let cString = nodeId.withCString({ opcua_read_datatype(ptr, $0) }) else {
            return nil
        }

        let dataType = String(cString: cString)
        opcua_free_string(cString)
        return dataType
    }

    // MARK: - Write Operations

    func writeValue(nodeId: String, value: String, dataType: String?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard let ptr = clientPtr, isConnected else { return false }

        let normalizedType = (dataType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalizedType {
        case "boolean":
            guard let boolValue = parseBool(value) else { return false }
            return nodeId.withCString { nodeIdPtr in
                opcua_write_value_bool(ptr, nodeIdPtr, boolValue)
            }
        case "int16":
            guard let intValue = Int16(value) else { return false }
            return nodeId.withCString { nodeIdPtr in
                opcua_write_value_int16(ptr, nodeIdPtr, intValue)
            }
        case "int32":
            guard let intValue = Int32(value) else { return false }
            return nodeId.withCString { nodeIdPtr in
                opcua_write_value_int32(ptr, nodeIdPtr, intValue)
            }
        case "int64":
            guard let intValue = Int64(value) else { return false }
            return nodeId.withCString { nodeIdPtr in
                opcua_write_value_int64(ptr, nodeIdPtr, intValue)
            }
        case "uint16":
            guard let intValue = UInt16(value) else { return false }
            return nodeId.withCString { nodeIdPtr in
                opcua_write_value_uint16(ptr, nodeIdPtr, intValue)
            }
        case "uint32":
            guard let intValue = UInt32(value) else { return false }
            return nodeId.withCString { nodeIdPtr in
                opcua_write_value_uint32(ptr, nodeIdPtr, intValue)
            }
        case "uint64":
            guard let intValue = UInt64(value) else { return false }
            return nodeId.withCString { nodeIdPtr in
                opcua_write_value_uint64(ptr, nodeIdPtr, intValue)
            }
        case "float":
            guard let floatValue = Float(value) else { return false }
            return nodeId.withCString { nodeIdPtr in
                opcua_write_value_float(ptr, nodeIdPtr, floatValue)
            }
        case "double":
            guard let doubleValue = Double(value) else { return false }
            return nodeId.withCString { nodeIdPtr in
                opcua_write_value_double(ptr, nodeIdPtr, doubleValue)
            }
        case "string", "localizedtext":
            return value.withCString { valuePtr in
                return nodeId.withCString { nodeIdPtr in
                    opcua_write_value_string(ptr, nodeIdPtr, valuePtr)
                }
            }
        default:
            // Fallback to string when type is unknown
            return value.withCString { valuePtr in
                return nodeId.withCString { nodeIdPtr in
                    opcua_write_value_string(ptr, nodeIdPtr, valuePtr)
                }
            }
        }
    }

    private func parseBool(_ value: String) -> Bool? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "true", "1", "yes", "y", "on":
            return true
        case "false", "0", "no", "n", "off":
            return false
        default:
            return nil
        }
    }
    
    // MARK: - Subscription Management
    
    private var dataChangeCallbacks: [String: (String, Date) -> Void] = [:]
    var subscriptionId: UInt32?
    private var monitoredItems: [String: UInt32] = [:] // nodeId -> monitoredItemId
    
    func createSubscription(publishingInterval: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard let ptr = clientPtr, isConnected else { return false }
        
        let subId = opcua_create_subscription(ptr, publishingInterval)
        if subId > 0 {
            subscriptionId = subId
            print("✅ Created subscription with ID: \(subId)")
            
            // Start a timer to process subscriptions
            startSubscriptionProcessing()
            return true
        }
        
        print("❌ Failed to create subscription")
        return false
    }
    
    func deleteSubscription() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard let ptr = clientPtr, 
              isConnected,
              let subId = subscriptionId else { return false }
        
        let success = opcua_delete_subscription(ptr, subId)
        if success {
            subscriptionId = nil
            monitoredItems.removeAll()
            dataChangeCallbacks.removeAll()
            stopSubscriptionProcessing()
            print("✅ Deleted subscription")
        }
        return success
    }
    
    func addMonitoredItem(nodeId: String, 
                         samplingInterval: Double,
                         onChange: @escaping (String, Date) -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard let ptr = clientPtr,
              isConnected,
              let subId = subscriptionId else { return false }
        
        // Check if already monitored to prevent duplicates
        if let existingId = monitoredItems[nodeId] {
            print("⚠️ Item \(nodeId) is already monitored with ID: \(existingId). Updating callback.")
            dataChangeCallbacks[nodeId] = onChange
            return true
        }
        
        // Store the Swift callback
        dataChangeCallbacks[nodeId] = onChange
        
        // Add the monitored item (no callback parameter needed anymore)
        let monItemId = opcua_add_monitored_item(ptr, subId, nodeId, samplingInterval)
        
        if monItemId > 0 {
            monitoredItems[nodeId] = monItemId
            print("✅ Added monitored item for \(nodeId) with ID: \(monItemId)")
            return true
        }
        
        print("❌ Failed to add monitored item for \(nodeId)")
        dataChangeCallbacks.removeValue(forKey: nodeId)
        return false
    }
    
    func removeMonitoredItem(nodeId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard let ptr = clientPtr,
              isConnected,
              let subId = subscriptionId,
              let monItemId = monitoredItems[nodeId] else { return false }
        
        let success = opcua_remove_monitored_item(ptr, subId, monItemId)
        if success {
            monitoredItems.removeValue(forKey: nodeId)
            dataChangeCallbacks.removeValue(forKey: nodeId)
            print("✅ Removed monitored item for \(nodeId)")
        }
        return success
    }
    
    private func handleDataChange(nodeId: String, value: String, timestamp: Date) {
        // Callback might be called within lock, but callback itself is swift code.
        // It calls external closures. 
        // We should be careful not to deadlock if callback calls client method back.
        // However, handleDataChange is called from processSubscriptions which HOLDS lock.
        // If the callback calls e.g. readValue, it will try to acquire lock (Reentrant/Recursive), which is fine.
        
        if let callback = dataChangeCallbacks[nodeId] {
            callback(value, timestamp)
        }
    }
    
    // Runs the open62541 client loop. This keeps sessions alive even before a
    // subscription is created, and also dispatches subscription notifications.
    private var processingTask: Task<Void, Never>?
    
    private func startSubscriptionProcessing() {
        // Stop existing task if any
        stopSubscriptionProcessing()
        
        // Start a polling task for the client loop. Shared state is still protected
        // with the recursive lock because callbacks can call back into the client.
        processingTask = Task(priority: .userInitiated) { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                
                self.processSubscriptionsSync()
                
                // sleep for 100ms
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
    
    private func stopSubscriptionProcessing() {
        processingTask?.cancel()
        processingTask = nil
    }
    
    private func processSubscriptionsSync() {
        // Need to acquire lock to safely access clientPtr and C functions
        lock.lock()
        defer { lock.unlock() }
        
        guard let ptr = clientPtr, isConnected else { return }
        
        // Process subscriptions with 10ms timeout to allow network I/O
        // This is important because we are running in a loop and don't want to block
        // the thread unnecessarily for long periods, but 0 might be too aggressive.
        opcua_process_subscriptions(ptr, 10)
        
        // Poll for value changes on all monitored items
        let currentItems = monitoredItems
        
        for (nodeId, _) in currentItems {
            // Check if value has changed
            if opcua_has_value_changed(ptr, nodeId) {
                // Get the new value
                if let valuePtr = opcua_get_monitored_value(ptr, nodeId) {
                    let value = String(cString: valuePtr)
                    opcua_free_string(valuePtr)
                    
                    // Get the timestamp from OPC UA (100ns intervals since 1601)
                    // Convert to Unix timestamp (seconds since 1970)
                    let timestampSeconds = opcua_get_monitored_timestamp(ptr, nodeId)
                    let unixOffset: Double = 11_644_473_600
                    let timestamp = Date(timeIntervalSince1970: timestampSeconds - unixOffset)

                    handleDataChange(nodeId: nodeId, value: value, timestamp: timestamp)
                }
            }
        }
    }
    
    // MARK: - Connection Status
    
    var connectionStatus: Bool {
        return isConnected
    }
}

// MARK: - Supporting Data Structures

struct SimpleOPCUANode: Identifiable, Hashable {
    let id = UUID()
    let nodeId: String
    let browseName: String
    let displayName: String
    let nodeClass: String
    var value: Any?
    var dataType: String?
    
    // For Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(nodeId)
    }
    
    static func == (lhs: SimpleOPCUANode, rhs: SimpleOPCUANode) -> Bool {
        lhs.nodeId == rhs.nodeId
    }
}
