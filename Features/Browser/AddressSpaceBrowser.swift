import SwiftUI
import Combine

struct AddressSpaceBrowser: View {
    @EnvironmentObject var appState: AppState
    @State private var nodes: [NodeInfo] = []
    @State private var selectedNode: NodeInfo?
    @State private var searchText = ""
    @State private var showNodeDetails = false
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var reloadAttempts = 0
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Server Selection Section
                ServerSelectionHeader(
                    loadAddressSpace: loadAddressSpaceDetached,
                    nodes: $nodes
                )
                
                Divider()
                
                // Address Space Content
                Group {
                    if appState.selectedServer == nil {
                        EmptyServerSelectionView()
                    } else if nodes.isEmpty && !isLoading {
                        EmptyAddressSpaceView(message: loadError)
                    } else {
                        NavigationSplitView {
                            TreeNavigationView(
                                nodes: $nodes,
                                selectedNode: $selectedNode,
                                searchText: $searchText
                            )
                            #if os(macOS)
                            .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 500)
                            #endif
                        } detail: {
                            if let node = selectedNode {
                                NodeDetailView(node: node)
                            } else {
                                EmptyNodeSelectionView()
                            }
                        }
                    }
                }
            }
            if isLoading {
                AddressSpaceLoadingOverlay()
            }
        }
        .navigationTitle("Address Space Browser")
        .searchable(text: $searchText, prompt: "Search nodes...")
        .toolbar {
            ToolbarItemGroup {
                Button(action: expandAll) {
                    Label("Expand All", systemImage: "plus.square")
                }
                
                Button(action: collapseAll) {
                    Label("Collapse All", systemImage: "minus.square")
                }
                
                Divider()
                
                if selectedNode != nil {
                    Button(action: { showNodeDetails = true }) {
                        Label("Node Details", systemImage: "info.circle")
                    }
                }
                
                Button(action: refreshNodes) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .sheet(isPresented: $showNodeDetails) {
            if let node = selectedNode {
                NodePropertiesView(node: node)
            }
        }
        .onAppear {
            // Load address space when the browse view appears.
            Task.detached {
                await loadAddressSpaceDetached()
            }
        }
        .onChange(of: appState.selectedTab) { oldTab, newTab in
            // Refresh address space whenever browse tab is selected (unless already loading)
            if newTab == .browse && !isLoading {
                Task.detached {
                    await loadAddressSpaceDetached()
                }
            }
        }
    }
    
    func expandAll() {
        withAnimation {
            setExpansionState(nodes, isExpanded: true)
        }
    }
    
    func collapseAll() {
        withAnimation {
            setExpansionState(nodes, isExpanded: false)
        }
    }
    
    func setExpansionState(_ nodes: [NodeInfo], isExpanded: Bool) {
        for node in nodes {
            node.isExpanded = isExpanded
            if let children = node.children {
                setExpansionState(children, isExpanded: isExpanded)
            }
        }
    }
    
    func refreshNodes() {
        loadError = nil
        reloadAttempts = 0
        Task.detached {
            await loadAddressSpaceDetached()
        }
    }
    
    @MainActor
    func loadAddressSpaceDetached() async {
        print("🌐🌐🌐 XCODE DEBUG: Address space browser loading started")
        print("XCODE DEBUG: This is the loadAddressSpaceDetached function")
        
        // Get server and manager references on MainActor first
        let server = appState.selectedServer
        let manager = appState.connectionManager
        
        guard let selectedServer = server else {
            print("❌❌❌ XCODE DEBUG: No server selected for address space browse")
            nodes = []
            isLoading = false
            return
        }
        
        print("🎯🎯🎯 XCODE DEBUG: Loading address space for server: \(selectedServer.name) (\(selectedServer.endpoint))")
        isLoading = true
        loadError = nil
        
        // Do the async work in a detached context
        var loadedNodes = await Task.detached {
            print("🔍 DEBUG: About to check connection status for browse operation")
            
            // Check connection without accessing @Published properties
            let status = await MainActor.run {
                manager.getConnectionStatus(for: selectedServer)
            }
            print("📊 DEBUG: Connection status for browse: \(status)")
            
            guard status == .connected else {
                print("❌ DEBUG: Not connected - cannot browse address space")
                return [NodeInfo]()
            }
            
            print("📁 DEBUG: Starting browse address space operation...")
            // Browse nodes
            let nodes = await manager.browseAddressSpace(for: selectedServer)
            print("✅ DEBUG: Browse address space completed - found \(nodes.count) nodes")
            return nodes
        }.value

        if loadedNodes.isEmpty, reloadAttempts < 1 {
            reloadAttempts += 1
            await MainActor.run {
                loadError = "No data returned. Retrying connection..."
            }
            await MainActor.run {
                manager.disconnectFromServer(selectedServer)
            }
            let reconnected = await manager.connectToServer(selectedServer)
            if reconnected {
                loadedNodes = await manager.browseAddressSpace(for: selectedServer)
            }
        }
        
        // Update UI back on MainActor
        nodes = loadedNodes
        isLoading = false
        if loadedNodes.isEmpty {
            loadError = "No address space data available. Check server status and try again."
        }
        print("🎨 DEBUG: Address space browser UI updated with \(loadedNodes.count) nodes")
    }
}

struct TreeNavigationView: View {
    @Binding var nodes: [NodeInfo]
    @Binding var selectedNode: NodeInfo?
    @Binding var searchText: String
    
    var body: some View {
        List(selection: $selectedNode) {
            ForEach(nodes) { node in
                RecursiveNodeView(node: node, selectedNode: $selectedNode)
            }
        }
        .listStyle(SidebarListStyle())
    }
}

struct RecursiveNodeView: View {
    @ObservedObject var node: NodeInfo
    @Binding var selectedNode: NodeInfo?
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        if node.hasChildren {
            DisclosureGroup(
                isExpanded: $node.isExpanded,
                content: {
                    if node.isLoading {
                        ProgressView()
                            .padding(.leading)
                    } else if let children = node.children {
                        ForEach(children) { child in
                            RecursiveNodeView(node: child, selectedNode: $selectedNode)
                        }
                    } else {
                        EmptyView()
                    }
                },
                label: {
                    NodeRow(node: node, isSelected: selectedNode == node)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedNode = node
                        }
                }
            )
            .onChange(of: node.isExpanded) { _, isExpanded in
                if isExpanded {
                    if node.children == nil {
                        loadChildren()
                    }
                }
            }
        } else {
            NodeRow(node: node, isSelected: selectedNode == node)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedNode = node
                }
        }
    }
    
    func loadChildren() {
        guard !node.isLoading else { return }
        node.isLoading = true
        
        Task {
            guard let server = appState.selectedServer else { return }
            
            // Artificial delay to show loading state if needed, or just let it be fast
            let children = await appState.connectionManager.browseChildNodes(for: server, parentNodeId: node.nodeId)
            
            await MainActor.run {
                node.children = children
                node.hasChildren = !children.isEmpty
                node.isLoading = false
            }
        }
    }
}

struct NodeRow: View {
    @ObservedObject var node: NodeInfo // Changed to ObservedObject
    var isSelected: Bool = false
    @State private var isHovered = false
    @State private var cachedValue: String = "—"
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.nodeClass.systemImage)
                .font(.system(size: 14))
                .foregroundColor(node.nodeClass.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(node.displayName)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    // Node type badge
                    Text(node.nodeClass.rawValue.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : node.nodeClass.color)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected ? .white.opacity(0.2) : node.nodeClass.color.opacity(0.1))
                        )
                }
                
                Text(node.nodeId)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if node.nodeClass == .variable {
                HStack(spacing: 6) {
                    Text(cachedValue)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(isSelected ? .white : .blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isSelected ? .white.opacity(0.2) : Color.blue.opacity(0.1))
                        )
                    
                    Circle()
                        .fill(node.quality.color)
                        .frame(width: 8, height: 8)
                }
            }
            
            if isHovered || isSelected {
                Menu {
                    Button(action: { readCurrentValue() }) {
                        Label("Read Value", systemImage: "arrow.down.circle")
                    }
                    Button(action: {}) {
                        Label("Write Value", systemImage: "arrow.up.circle")
                    }
                    .disabled(node.nodeClass != .variable)
                    Divider()
                    Button(action: { addToSubscription() }) {
                        Label("Add to Subscription", systemImage: "bell.badge.fill")
                    }
                    .disabled(node.nodeClass != .variable)
                    Button(action: { startMonitoring() }) {
                        Label("Monitor", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .disabled(node.nodeClass != .variable)
                    Button(action: { addToAnalytics() }) {
                        Label("Add to Analytics Chart", systemImage: "chart.xyaxis.line")
                    }
                    .disabled(node.nodeClass != .variable)
                    Divider()
                    Button(action: {}) {
                        Label("Copy Node ID", systemImage: "doc.on.doc")
                    }
                    Button(action: {}) {
                        Label("Properties", systemImage: "info.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .onAppear {
            if node.nodeClass == .variable {
                cachedValue = node.value ?? "—"
            }
        }
    }
    
    private func updateCachedValue() {
        if node.nodeClass == .variable {
            Task { @MainActor in
                // Safely access connection manager on main actor
                let liveValue = appState.connectionManager.getLiveValue(for: node.nodeId)
                let newValue = liveValue ?? node.value ?? "—"
                if newValue != cachedValue {
                    cachedValue = newValue
                }
            }
        }
    }
    
    private func addToSubscription() {
        guard let selectedServer = appState.selectedServer else { return }
        
        // Check if subscription exists for this server
        let existingSubscription = appState.subscriptions.first { $0.serverId == selectedServer.id }
        
        if let subscription = existingSubscription {
            // Add to existing subscription
            let newItem = MonitoredItem(
                nodeId: node.nodeId,
                displayName: node.displayName,
                samplingInterval: 1000.0,
                queueSize: 10,
                discardOldest: true,
                currentValue: cachedValue,
                timestamp: Date(),
                quality: node.quality
            )
            
            // Use AppState's persistence method
            appState.addMonitoredItem(newItem, to: subscription.id)
            
            // Add monitored item to actual OPC UA subscription
            Task {
                _ = await appState.connectionManager.addMonitoredItem(
                    for: selectedServer,
                    nodeId: node.nodeId,
                    samplingInterval: 1000.0
                )
            }
            
            print("Added \(node.displayName) to existing subscription")
        } else {
            // Create new subscription dialog
            DispatchQueue.main.async {
                // We'll create a subscription creation dialog here
                self.showSubscriptionCreationDialog()
            }
        }
    }
    
    private func startMonitoring() {
        addToSubscription()
        // Switch to monitoring tab - defer to avoid "Publishing changes from within view updates" error
        DispatchQueue.main.async {
            appState.selectedTab = .monitor
        }
    }
    
    private func showSubscriptionCreationDialog() {
        guard let selectedServer = appState.selectedServer else { return }
        
        // Create a new subscription with this node
        let newItem = MonitoredItem(
            nodeId: node.nodeId,
            displayName: node.displayName,
            samplingInterval: 1000.0,
            queueSize: 10,
            discardOldest: true,
            currentValue: cachedValue,
            timestamp: Date(),
            quality: node.quality
        )
        
        let newSubscription = Subscription(
            name: "Subscription for \(selectedServer.name)",
            serverId: selectedServer.id,
            publishingInterval: 1000.0,
            priority: 1,
            isActive: true,
            monitoredItems: [newItem]
        )
        
        // Use AppState's persistence method
        appState.saveSubscription(newSubscription)
        
        // Create actual OPC UA subscription and monitored item
        Task {
            let created = await appState.connectionManager.createSubscription(
                for: selectedServer,
                publishingInterval: newSubscription.publishingInterval
            )
            
            if created {
                // Add monitored item to the OPC UA subscription
                _ = await appState.connectionManager.addMonitoredItem(
                    for: selectedServer,
                    nodeId: node.nodeId,
                    samplingInterval: 1000.0
                )
            }
        }
        
        print("Created new subscription for \(selectedServer.name) with \(node.displayName)")
    }

    private func readCurrentValue() {
        guard let selectedServer = appState.selectedServer else { return }
        guard node.nodeClass == .variable else { return }
        
        Task {
            if let value = await appState.connectionManager.readNodeValue(for: selectedServer, nodeId: node.nodeId) {
                await MainActor.run {
                    cachedValue = value
                }
            }
        }
    }
    
    private func addToAnalytics() {
        guard let selectedServer = appState.selectedServer else { return }

        // Set connection manager reference if not already set
        AnalyticsManager.shared.connectionManager = appState.connectionManager

        // Add to analytics manager
        AnalyticsManager.shared.addMonitoredItem(
            nodeId: node.nodeId,
            displayName: node.displayName,
            server: selectedServer,
            unit: ""
        )

        // Switch to analytics workspace for trend analysis.
        DispatchQueue.main.async {
            appState.selectedTab = .analytics
        }
    }
}

struct NodeDetailView: View {
    let node: NodeInfo
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            NodeHeaderView(node: node)
            
            Picker("", selection: $selectedTab) {
                Text("Attributes").tag(0)
                Text("References").tag(1)
                Text("Value").tag(2)
                Text("History").tag(3)
            }
            .pickerStyle(.segmented)
            .padding()
            
            TabView(selection: $selectedTab) {
                AttributesView(node: node)
                    .tag(0)
                
                ReferencesView(node: node)
                    .tag(1)
                
                ValueView(node: node)
                    .tag(2)
                
                HistoryView(node: node)
                    .tag(3)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
        }
    }
}

struct NodeHeaderView: View {
    let node: NodeInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: node.nodeClass.systemImage)
                    .font(.title2)
                    .foregroundColor(node.nodeClass.color)
                
                VStack(alignment: .leading) {
                    Text(node.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(node.nodeId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                
                Spacer()
                
                if node.nodeClass == .variable {
                    VStack(alignment: .trailing) {
                        HStack {
                            Circle()
                                .fill(node.quality.color)
                                .frame(width: 10, height: 10)
                            Text(node.quality.rawValue)
                                .font(.caption)
                        }
                        
                        if let timestamp = node.timestamp {
                            Text(timestamp, format: .dateTime)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.secondarySystemBackground)
    }
}

struct AttributesView: View {
    let node: NodeInfo
    @EnvironmentObject var appState: AppState
    @State private var currentValue: String = "—"
    @State private var isRefreshing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Basic Attributes
                Group {
                    AttributeRow(label: "Node ID", value: node.nodeId)
                    AttributeRow(label: "Display Name", value: node.displayName)
                    AttributeRow(label: "Node Class", value: node.nodeClass.rawValue)
                    AttributeRow(label: "Browse Name", value: node.displayName)
                    
                    // Show actual value if it's a variable
                    if node.nodeClass == .variable {
                        HStack {
                            AttributeRow(label: "Current Value", value: currentValue)
                            
                            Button(action: refreshValue) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                    .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                            }
                            .buttonStyle(.plain)
                            .disabled(isRefreshing)
                        }
                        
                        AttributeRow(label: "Quality", value: node.quality.rawValue)
                        
                        if let timestamp = node.timestamp {
                            AttributeRow(label: "Last Updated", value: timestamp.formatted(.dateTime))
                        } else {
                            AttributeRow(label: "Last Updated", value: "—")
                        }
                    }
                }
                
                Divider()
                
                // Type Information
                Group {
                    if let dataType = node.dataType {
                        AttributeRow(label: "Data Type", value: dataType)
                    } else if node.nodeClass == .variable {
                        AttributeRow(label: "Data Type", value: "Unknown")
                    }
                    
                    AttributeRow(label: "Description", value: getDescription())
                }
                
                Divider()
                
                // Access Information (for Variables)
                if node.nodeClass == .variable {
                    Group {
                        AttributeRow(label: "Access Level", value: "Read/Write")
                        AttributeRow(label: "User Access Level", value: "Read/Write")
                        AttributeRow(label: "Minimum Sampling Interval", value: "100ms")
                        AttributeRow(label: "Historizing", value: "false")
                    }
                }
            }
            .padding()
        }
        .onAppear {
            // Initialize current value from node
            if node.nodeClass == .variable {
                currentValue = node.value ?? "—"
            }
        }
    }
    
    private func refreshValue() {
        guard let selectedServer = appState.selectedServer else { return }
        guard node.nodeClass == .variable else { return }
        
        isRefreshing = true
        
        Task {
            if let value = await appState.connectionManager.readNodeValue(for: selectedServer, nodeId: node.nodeId) {
                await MainActor.run {
                    currentValue = value
                    isRefreshing = false
                }
            } else {
                await MainActor.run {
                    currentValue = "Error reading value"
                    isRefreshing = false
                }
            }
        }
    }
    
    private func getDescription() -> String {
        switch node.nodeClass {
        case .object:
            return "Object node containing other nodes"
        case .variable:
            return "Variable node holding a value"
        case .method:
            return "Method that can be invoked"
        case .objectType:
            return "Defines the structure of an object"
        case .variableType:
            return "Defines the structure of a variable"
        case .referenceType:
            return "Defines relationships between nodes"
        case .dataType:
            return "Defines data type information"
        case .view:
            return "Subset of nodes for specific purposes"
        }
    }
}

struct ReferencesView: View {
    let node: NodeInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)

                    Text("References Not Available")
                        .font(.headline)

                    Text("Reference browsing requires full OPC UA protocol implementation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
            .padding()
        }
    }
}

struct ValueView: View {
    let node: NodeInfo
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var writeHistory: WriteHistoryManager
    @State private var newValue = ""
    @State private var isWriting = false
    @State private var writeMessage: String?
    @State private var writeSucceeded = false
    @State private var showWriteConfirmation = false
    @State private var pendingWriteValue: String?
    @State private var pendingDataType: String?
    @State private var showSmartWrite = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Current Value", systemImage: "tag.fill")
                        .font(.headline)
                    
                    Text(node.value ?? "No value")
                        .font(.system(size: 24, design: .monospaced))
                        .foregroundColor(.blue)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.1))
                        )
                }
                
                if node.nodeClass == .variable {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Write New Value", systemImage: "pencil.circle.fill")
                            .font(.headline)
                        
                        HStack {
                            TextField("Enter new value", text: $newValue)
                                .textFieldStyle(.roundedBorder)
                            
                            Button(action: { requestWrite(value: newValue, dataType: node.dataType) }) {
                                if isWriting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Write")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newValue.isEmpty || isWriting)
                        }

                        Button {
                            showSmartWrite = true
                        } label: {
                            Label("Smart Write", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isWriting)

                        if let message = writeMessage {
                            HStack(spacing: 6) {
                                Image(systemName: writeSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(writeSucceeded ? .green : .red)
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if node.nodeClass == .variable {
                    writeHistorySection
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    DetailRow(label: "Quality", value: node.quality.rawValue, color: node.quality.color)
                    DetailRow(label: "Timestamp", value: node.timestamp?.formatted() ?? "N/A")
                    DetailRow(label: "Server Timestamp", value: Date().formatted())
                    DetailRow(label: "Source", value: "Server")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.tertiarySystemGroupedBackground)
                )
            }
            .padding()
        }
        .alert("Confirm Write", isPresented: $showWriteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Write", role: .destructive) {
                performWrite()
            }
        } message: {
            Text(confirmMessage)
        }
        .sheet(isPresented: $showSmartWrite) {
            SmartDataInputForm(nodeInfo: node, initialDataType: mapToSmartType(node.dataType)) { parsedValue, dataType in
                let formatted = formatValueForWrite(parsedValue)
                requestWrite(value: formatted, dataType: mapToOpcType(dataType))
                showSmartWrite = false
            }
        }
    }

    private var confirmMessage: String {
        let value = pendingWriteValue ?? ""
        return "Are you sure you want to write '\(value)' to \(node.displayName)?"
    }

    @ViewBuilder
    private var writeHistorySection: some View {
        let entries = writeHistory.entries(for: node.nodeId, serverId: appState.selectedServer?.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Write History", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                if !entries.isEmpty {
                    Button("Clear") {
                        writeHistory.clearHistory(for: node.nodeId, serverId: appState.selectedServer?.id)
                    }
                    .font(.caption)
                }
            }

            if entries.isEmpty {
                Text("No write history yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(entries.prefix(5)) { entry in
                    HStack {
                        Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(entry.success ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.value)
                                .font(.caption)
                            Text(entry.timestamp.formatted())
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if let type = entry.dataType, !type.isEmpty {
                            Text(type)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.tertiarySystemGroupedBackground)
        )
    }

    private func requestWrite(value: String, dataType: String?) {
        pendingWriteValue = value
        pendingDataType = dataType
        showWriteConfirmation = true
    }

    private func performWrite() {
        guard let server = appState.selectedServer else {
            writeMessage = "No server selected"
            writeSucceeded = false
            return
        }

        isWriting = true
        let valueToWrite = pendingWriteValue ?? newValue
        let dataTypeToWrite = pendingDataType ?? node.dataType

        Task { @MainActor in
            let success = await appState.connectionManager.writeNodeValue(
                for: server,
                nodeId: node.nodeId,
                value: valueToWrite,
                dataType: dataTypeToWrite,
                nodeDisplayName: node.displayName
            )

            if success {
                newValue = ""
                writeMessage = "Value written successfully"
                writeSucceeded = true
            } else {
                writeMessage = "Write failed. Check value and connection."
                writeSucceeded = false
            }
            isWriting = false
            pendingWriteValue = nil
            pendingDataType = nil
        }
    }

    private func mapToSmartType(_ dataType: String?) -> SmartDataInputForm.OPCDataType? {
        let normalized = (dataType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "boolean":
            return .boolean
        case "byte", "uint8":
            return .byte
        case "int16":
            return .int16
        case "int32":
            return .int32
        case "int64":
            return .int64
        case "float":
            return .float
        case "double":
            return .double
        case "string", "localizedtext":
            return .string
        case "datetime":
            return .dateTime
        case "bytestring":
            return .byteString
        default:
            return nil
        }
    }

    private func mapToOpcType(_ dataType: SmartDataInputForm.OPCDataType) -> String? {
        switch dataType {
        case .boolean:
            return "Boolean"
        case .byte:
            return "Byte"
        case .int16:
            return "Int16"
        case .int32:
            return "Int32"
        case .int64:
            return "Int64"
        case .float:
            return "Float"
        case .double:
            return "Double"
        case .string:
            return "String"
        case .dateTime:
            return "DateTime"
        case .byteString:
            return "ByteString"
        case .array, .structure:
            return nil
        }
    }

    private func formatValueForWrite(_ value: Any) -> String {
        if let stringValue = value as? String {
            return stringValue
        }
        if let boolValue = value as? Bool {
            return boolValue ? "true" : "false"
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let dateValue = value as? Date {
            return ISO8601DateFormatter().string(from: dateValue)
        }
        if let arrayValue = value as? [String] {
            if let data = try? JSONSerialization.data(withJSONObject: arrayValue, options: []) {
                return String(data: data, encoding: .utf8) ?? arrayValue.description
            }
            return arrayValue.description
        }
        if let dictValue = value as? [String: String] {
            if let data = try? JSONSerialization.data(withJSONObject: dictValue, options: []) {
                return String(data: data, encoding: .utf8) ?? dictValue.description
            }
            return dictValue.description
        }
        return String(describing: value)
    }
}

struct HistoryView: View {
    let node: NodeInfo
    @State private var startDate = Date().addingTimeInterval(-86400)
    @State private var endDate = Date()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Time Range", systemImage: "calendar")
                        .font(.headline)
                    
                    DatePicker("Start", selection: $startDate)
                    DatePicker("End", selection: $endDate)
                    
                    Button(action: {}) {
                        Label("Load History", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("Historical Data", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    
                    Text("No historical data available")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.tertiarySystemGroupedBackground)
                        )
                }
            }
            .padding()
        }
    }
}

struct AttributeRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

struct ReferenceRow: View {
    let referenceType: String
    let targetNode: String
    let targetName: String
    
    var body: some View {
        HStack {
            Image(systemName: "link")
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading) {
                Text(referenceType)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text(targetName)
                        .font(.body)
                    Text(targetNode)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

struct EmptyNodeSelectionView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.fill.badge.gearshape")
                .font(.system(size: 72))
                .foregroundColor(.secondary)
            
            Text("Select a Node")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Choose a node from the tree to view its details")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NodePropertiesView: View {
    let node: NodeInfo
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            NodeDetailView(node: node)
                .navigationTitle("Node Properties")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
    }
}

// MARK: - Server Selection Header

struct ServerSelectionHeader: View {
    @EnvironmentObject var appState: AppState
    @State private var connectionStatus: ConnectionStatus = .disconnected
    @State private var connectedServers: [OPCUAServer] = []
    let loadAddressSpace: () async -> Void
    @Binding var nodes: [NodeInfo]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Select Connected Server")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                if appState.selectedServer != nil {
                    ConnectionStatusIndicator(status: connectionStatus)
                }
            }

            HStack {
                // Server Picker - Only shows connected servers
                if connectedServers.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("No connected servers available")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Picker("Server", selection: Binding(
                        get: { appState.selectedServer },
                        set: { newServer in
                            appState.selectedServer = newServer

                            if newServer != nil {
                                Task {
                                    // Check connection status immediately
                                    let status = appState.connectionManager.getConnectionStatus(for: newServer!)
                                    await MainActor.run {
                                        connectionStatus = status
                                    }

                                    // If already connected, browse immediately
                                    if status == .connected {
                                        await loadAddressSpace()
                                    }
                                }
                            }
                        }
                    )) {
                        Text("Select a server...").tag(nil as OPCUAServer?)

                        ForEach(connectedServers) { server in
                            Text(server.name)
                                .tag(server as OPCUAServer?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                }

                Spacer()

                // Only show Refresh/Disconnect buttons since we only show connected servers
                if let selectedServer = appState.selectedServer {
                    HStack(spacing: 8) {
                        Button("Refresh") {
                            Task {
                                await loadAddressSpace()
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("Disconnect") {
                            Task {
                                appState.connectionManager.disconnectFromServer(selectedServer)
                                updateConnectionStatus()
                                await refreshConnectedServers()
                                // Clear nodes when disconnecting
                                nodes.removeAll()
                                // Clear selection if no connected servers remain
                                if connectedServers.isEmpty {
                                    appState.selectedServer = nil
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .onAppear {
            updateConnectionStatus()
            Task {
                await refreshConnectedServers()
            }
        }
        .onChange(of: appState.selectedServer) { _, _ in
            updateConnectionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .opcuaConnectionChanged)) { _ in
            Task {
                await refreshConnectedServers()
            }
        }
    }

    private func refreshConnectedServers() async {
        var connected: [OPCUAServer] = []
        for server in appState.servers {
            let status = appState.connectionManager.getConnectionStatus(for: server)
            if status == .connected {
                connected.append(server)
            }
        }
        await MainActor.run {
            connectedServers = connected
            // If selected server is no longer connected, try to select first connected server
            if let selected = appState.selectedServer {
                if !connected.contains(where: { $0.id == selected.id }) {
                    appState.selectedServer = connected.first
                }
            } else if appState.selectedServer == nil && !connected.isEmpty {
                // Auto-select first connected server if none selected
                appState.selectedServer = connected.first
            }
        }
    }

    private func updateConnectionStatus() {
        guard let selectedServer = appState.selectedServer else {
            connectionStatus = .disconnected
            return
        }

        Task {
            let status = appState.connectionManager.getConnectionStatus(for: selectedServer)
            await MainActor.run {
                connectionStatus = status
            }
        }
    }

    @MainActor
    private func updateConnectionStatusAsync() async {
        guard let selectedServer = appState.selectedServer else {
            connectionStatus = .disconnected
            return
        }

        let status = appState.connectionManager.getConnectionStatus(for: selectedServer)
        connectionStatus = status
    }
}

// MARK: - Connection Status Indicator

struct ConnectionStatusIndicator: View {
    let status: ConnectionStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            
            Text(status.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Empty State Views

struct EmptyServerSelectionView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 72))
                .foregroundColor(.secondary)

            Text("No Connected Servers")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Connect to a server from the Servers page first, then select it from the dropdown above to browse its address space")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: {
                appState.selectedTab = .servers
            }) {
                Label("Go to Servers", systemImage: "server.rack")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyAddressSpaceView: View {
    let message: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 72))
                .foregroundColor(.secondary)
            
            Text("No Address Space Data")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message ?? "Connect to the server and click 'Browse' to load the address space")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AddressSpaceLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView("Loading address space…")
                    .progressViewStyle(.circular)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondarySystemGroupedBackground)
            )
        }
    }
}
