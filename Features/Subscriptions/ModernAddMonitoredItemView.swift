import SwiftUI

struct ModernAddMonitoredItemView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var monitoringState: ModernMonitoringState
    var appState: AppState
    
    @State private var nodeId = ""
    @State private var displayName = ""
    @State private var selectedServer: OPCUAServer?
    @State private var samplingInterval = "1000"
    @State private var queueSize = "10"
    @State private var discardOldest = true
    @State private var dataChangeFilter: DataChangeFilter = .status
    @State private var deadbandType: DeadbandType = .none
    @State private var deadbandValue = ""
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var showAdvancedOptions = false
    @State private var selectedNodes: Set<String> = []
    @State private var isBrowsing = false
    @State private var availableNodes: [NodeInfo] = []
    @State private var showingAddressSpaceBrowser = false
    
    enum DataChangeFilter: String, CaseIterable, Identifiable {
        case status = "Status"
        case statusValue = "Status + Value"
        case statusTimestamp = "Status + Timestamp"
        
        var id: String { rawValue }
    }
    
    enum DeadbandType: String, CaseIterable, Identifiable {
        case none = "None"
        case absolute = "Absolute"
        case percent = "Percent"
        
        var id: String { rawValue }
    }
    
    var connectedServers: [OPCUAServer] {
        appState.servers.filter { appState.connectionManager.isConnected(to: $0) }
    }
    
    var isFormValid: Bool {
        !nodeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedServer != nil &&
        Int(samplingInterval) != nil &&
        Int(queueSize) != nil
    }
    
    var body: some View {
        Group {
            if showingAddressSpaceBrowser, let selectedServer {
                MonitoredItemAddressSpacePicker(
                    server: selectedServer,
                    appState: appState,
                    onSelect: { node in
                        applySelectedNode(node)
                        showingAddressSpaceBrowser = false
                    },
                    onCancel: {
                        showingAddressSpaceBrowser = false
                    }
                )
            } else {
                formContent
            }
        }
        .frame(width: showingAddressSpaceBrowser ? 900 : 650, height: showingAddressSpaceBrowser ? 650 : 700)
        .background(DesignSystem.Colors.background)
        .onAppear {
            // Auto-select default server
            if selectedServer == nil, let defaultServer = connectedServers.first(where: { $0.isDefault }) {
                selectedServer = defaultServer
            } else if selectedServer == nil, let firstServer = connectedServers.first {
                selectedServer = firstServer
            }
        }
    }

    private var formContent: some View {
        VStack(spacing: 0) {
            // Header
            DialogHeader(
                title: "Add Monitored Item",
                subtitle: "Configure a new node to monitor in real-time",
                icon: "chart.line.uptrend.xyaxis.circle",
                onDismiss: { dismiss() }
            )
            
            // Content
            ModernForm {
                // Server Selection
                FormSection("Server Selection") {
                    if connectedServers.isEmpty {
                        EmptyStateCard(
                            icon: "server.rack",
                            message: "No connected servers available",
                            hint: "Connect to a server first from the Servers page"
                        )
                    } else {
                        ModernPicker(
                            "Select Server",
                            selection: $selectedServer,
                            icon: "server.rack"
                        ) {
                            Text("Choose a server...").tag(nil as OPCUAServer?)
                            ForEach(connectedServers) { server in
                                HStack {
                                    StatusIndicator(isConnected: true)
                                    Text(server.name)
                                    if server.isDefault {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(DesignSystem.Colors.primary)
                                            .font(.caption)
                                    }
                                }
                                .tag(server as OPCUAServer?)
                            }
                        }
                    }
                }
                
                // Node Configuration
                FormSection("Node Configuration") {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        // Node Browser Button
                        if selectedServer != nil {
                            Button(action: { openAddressSpaceBrowser() }) {
                                HStack {
                                    Image(systemName: "folder.badge.gearshape")
                                    Text("Browse Address Space")
                                    Spacer()
                                    if isBrowsing {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                            .scaleEffect(0.7)
                                    }
                                }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(isBrowsing)
                        }
                        
                        ModernTextField(
                            title: "Node ID",
                            text: $nodeId,
                            icon: "number.circle",
                            placeholder: "ns=2;s=MyVariable or ns=2;i=1234"
                        )
                        
                        ModernTextField(
                            title: "Display Name",
                            text: $displayName,
                            icon: "textformat",
                            placeholder: "Human-readable name for this node"
                        )
                        
                        // Node ID Format Help
                        DisclosureGroup("Node ID Format Help") {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                                FormatHelpRow(
                                    format: "ns=2;s=MyVariable",
                                    description: "String identifier in namespace 2"
                                )
                                FormatHelpRow(
                                    format: "ns=2;i=1234",
                                    description: "Numeric identifier in namespace 2"
                                )
                                FormatHelpRow(
                                    format: "ns=1;g=550e8400-e29b-41d4-a716",
                                    description: "GUID identifier in namespace 1"
                                )
                                FormatHelpRow(
                                    format: "ns=0;i=2258",
                                    description: "Standard OPC UA Server node"
                                )
                            }
                            .padding(DesignSystem.Spacing.small)
                            .background(DesignSystem.Colors.info.opacity(0.05))
                            .cornerRadius(DesignSystem.CornerRadius.small)
                        }
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                }
                
                // Sampling Configuration
                FormSection("Sampling Configuration") {
                    HStack(spacing: DesignSystem.Spacing.medium) {
                        ModernTextField(
                            title: "Sampling Interval (ms)",
                            text: $samplingInterval,
                            icon: "timer",
                            placeholder: "1000"
                        )
                        
                        ModernTextField(
                            title: "Queue Size",
                            text: $queueSize,
                            icon: "square.stack.3d.up",
                            placeholder: "10"
                        )
                    }
                    
                    Toggle(isOn: $discardOldest) {
                        HStack {
                            Image(systemName: "arrow.up.trash")
                                .foregroundColor(DesignSystem.Colors.primary)
                            VStack(alignment: .leading) {
                                Text("Discard Oldest")
                                    .font(DesignSystem.Typography.body)
                                Text("Remove oldest values when queue is full")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.secondaryText)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                }
                
                // Advanced Options
                DisclosureGroup(isExpanded: $showAdvancedOptions) {
                    FormSection {
                        ModernPicker(
                            "Data Change Filter",
                            selection: $dataChangeFilter,
                            icon: "line.3.horizontal.decrease.circle"
                        ) {
                            ForEach(DataChangeFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        
                        ModernPicker(
                            "Deadband Type",
                            selection: $deadbandType,
                            icon: "waveform.path.ecg"
                        ) {
                            ForEach(DeadbandType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        
                        if deadbandType != .none {
                            ModernTextField(
                                title: "Deadband Value",
                                text: $deadbandValue,
                                icon: "plusminus",
                                placeholder: deadbandType == .percent ? "5.0" : "0.5"
                            )
                        }
                        
                        // Info about deadband
                        if deadbandType != .none {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(DesignSystem.Colors.info)
                                Text(deadbandType == .percent ? 
                                     "Only report changes greater than this percentage of the range" :
                                     "Only report changes greater than this absolute value")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.secondaryText)
                            }
                            .padding(DesignSystem.Spacing.small)
                            .background(DesignSystem.Colors.info.opacity(0.1))
                            .cornerRadius(DesignSystem.CornerRadius.small)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: showAdvancedOptions ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12))
                        Text("Advanced Options")
                            .font(DesignSystem.Typography.headline)
                        Spacer()
                    }
                }
                
                // Error Display
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(DesignSystem.Colors.error)
                        Text(error)
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.error)
                    }
                    .padding(DesignSystem.Spacing.medium)
                    .background(DesignSystem.Colors.error.opacity(0.1))
                    .cornerRadius(DesignSystem.CornerRadius.small)
                }
            }
            
            // Footer
            DialogFooter(
                primaryAction: addMonitoredItem,
                primaryLabel: isAdding ? "Adding..." : "Add Item",
                cancelAction: { dismiss() },
                isPrimaryDisabled: !isFormValid || isAdding
            )
        }
    }
    
    // MARK: - Helper Views
    
    struct EmptyStateCard: View {
        let icon: String
        let message: String
        let hint: String?
        
        var body: some View {
            VStack(spacing: DesignSystem.Spacing.small) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(DesignSystem.Colors.tertiaryText)
                
                Text(message)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                
                if let hint = hint {
                    Text(hint)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.tertiaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(DesignSystem.Spacing.large)
            .background(DesignSystem.Colors.tertiaryBackground)
            .cornerRadius(DesignSystem.CornerRadius.medium)
        }
    }
    
    struct FormatHelpRow: View {
        let format: String
        let description: String
        
        var body: some View {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
                Text(format)
                    .font(DesignSystem.Typography.monospacedCaption)
                    .foregroundColor(DesignSystem.Colors.primary)
                Spacer()
                Text(description)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        }
    }
    
    struct StatusIndicator: View {
        let isConnected: Bool
        
        var body: some View {
            Circle()
                .fill(isConnected ? DesignSystem.Colors.success : DesignSystem.Colors.error)
                .frame(width: 8, height: 8)
        }
    }
    
    // MARK: - Actions
    
    func openAddressSpaceBrowser() {
        guard let selectedServer else {
            errorMessage = "Please select a connected server before browsing the address space."
            return
        }

        guard appState.connectionManager.isConnected(to: selectedServer) else {
            errorMessage = "No OPC UA server is connected for \(selectedServer.name)."
            return
        }

        errorMessage = nil
        showingAddressSpaceBrowser = true
    }

    func applySelectedNode(_ node: NodeInfo) {
        nodeId = node.nodeId
        displayName = node.displayName
        errorMessage = nil
    }
    
    func addMonitoredItem() {
        isAdding = true
        errorMessage = nil
        
        guard let server = selectedServer else {
            errorMessage = "Please select a server"
            isAdding = false
            return
        }
        
        // Find or create subscription
        let subscription = appState.subscriptions.first { $0.serverId == server.id }
        let newItem = MonitoredItem(
            nodeId: nodeId.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            samplingInterval: Double(samplingInterval) ?? 1000,
            queueSize: Int(queueSize) ?? 10,
            discardOldest: discardOldest,
            currentValue: nil,
            timestamp: nil,
            quality: .good
        )
        
        if let subscription = subscription {
            appState.addMonitoredItem(newItem, to: subscription.id)
        } else {
            // Create new subscription
            let newSubscription = Subscription(
                name: "Subscription for \(server.name)",
                serverId: server.id,
                publishingInterval: 1000.0,
                priority: 1,
                isActive: true,
                monitoredItems: [newItem]
            )
            appState.saveSubscription(newSubscription)
        }
        
        Task {
            let success = await appState.connectionManager.addMonitoredItem(
                for: server,
                nodeId: nodeId.trimmingCharacters(in: .whitespacesAndNewlines),
                samplingInterval: Double(samplingInterval) ?? 1000
            )
            
            await MainActor.run {
                if success {
                    dismiss()
                } else {
                    errorMessage = "Failed to add monitored item. Please check the node ID and try again."
                    isAdding = false
                }
            }
        }
    }
}

private struct MonitoredItemAddressSpacePicker: View {
    let server: OPCUAServer
    var appState: AppState
    let onSelect: (NodeInfo) -> Void
    let onCancel: () -> Void

    @State private var rootNodes: [NodeInfo] = []
    @State private var childrenByNodeId: [String: [NodeInfo]] = [:]
    @State private var expandedNodeIds = Set<String>()
    @State private var loadingNodeIds = Set<String>()
    @State private var selectedNode: NodeInfo?
    @State private var searchText = ""
    @State private var isLoadingRoot = false
    @State private var errorMessage: String?

    private var selectableNodes: [NodeInfo] {
        flatten(rootNodes).filter(isSubscribable)
    }

    private var filteredNodes: [NodeInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return selectableNodes }
        return selectableNodes.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            $0.nodeId.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                browserPane
                    .frame(minWidth: 420, idealWidth: 520)

                Divider()

                selectionPane
                    .frame(minWidth: 280, idealWidth: 320)
            }
            .navigationTitle("Select Node")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { onCancel() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Node") {
                        if let selectedNode {
                            onSelect(selectedNode)
                        }
                    }
                    .disabled(selectedNode == nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 780, minHeight: 600)
        #endif
        .onAppear(perform: loadRootNodes)
    }

    private var browserPane: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                Text(server.name)
                    .font(DesignSystem.Typography.headline)
                Text("Expand folders and choose a Variable node. Objects and Views are browse containers, not subscribable monitored items.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DesignSystem.Colors.tertiaryText)
                TextField("Search loaded variable nodes...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(DesignSystem.Spacing.xSmall)
            .background(DesignSystem.Colors.tertiaryBackground)
            .cornerRadius(DesignSystem.CornerRadius.small)

            if isLoadingRoot {
                VStack(spacing: DesignSystem.Spacing.small) {
                    ProgressView()
                    Text("Loading address space...")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Address Space Unavailable",
                    systemImage: "network.slash",
                    description: Text(errorMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.xSmall) {
                        ForEach(filteredNodes) { node in
                            PickerNodeSearchRow(
                                node: node,
                                isSelected: selectedNode?.nodeId == node.nodeId,
                                onSelect: { selectNode(node) }
                            )
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.xSmall)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                        ForEach(rootNodes.filter(isVisibleInPicker)) { node in
                            PickerNodeTreeRow(
                                node: node,
                                level: 0,
                                selectedNodeId: selectedNode?.nodeId,
                                expandedNodeIds: expandedNodeIds,
                                loadingNodeIds: loadingNodeIds,
                                childrenByNodeId: childrenByNodeId,
                                onToggle: toggleNode,
                                onSelect: selectNode
                            )
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.xSmall)
                }
            }
        }
        .padding()
        .background(DesignSystem.Colors.background)
    }

    private var selectionPane: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
            SectionHeader("NODE CONFIGURATION", icon: "tag")

            if let selectedNode {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    Text(selectedNode.displayName)
                        .font(DesignSystem.Typography.headline)
                    Text(selectedNode.nodeId)
                        .font(DesignSystem.Typography.monospacedCaption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

                    if let dataType = selectedNode.dataType {
                        Label(dataType, systemImage: "number")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }

                    Label("This node will populate the Node ID and Display Name fields.", systemImage: "checkmark.circle.fill")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.success)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.background)
                .cornerRadius(DesignSystem.CornerRadius.medium)
            } else {
                Text("Select a Variable node from the address space.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignSystem.Colors.background)
                    .cornerRadius(DesignSystem.CornerRadius.medium)
            }

            Spacer()
        }
        .padding()
        .background(DesignSystem.Colors.tertiaryBackground)
    }

    private func loadRootNodes() {
        guard rootNodes.isEmpty, !isLoadingRoot else { return }
        guard appState.connectionManager.isConnected(to: server) else {
            errorMessage = "Connect to \(server.name) before browsing nodes."
            return
        }

        isLoadingRoot = true
        errorMessage = nil

        Task {
            let nodes = await appState.connectionManager.browseAddressSpace(for: server, maxDepth: 1)
                .filter(isVisibleInPicker)

            await MainActor.run {
                rootNodes = nodes
                isLoadingRoot = false
                if nodes.isEmpty {
                    errorMessage = "The server returned no browsable nodes."
                }
            }
        }
    }

    private func toggleNode(_ node: NodeInfo) {
        guard isExpandable(node) else {
            selectNode(node)
            return
        }

        if expandedNodeIds.contains(node.nodeId) {
            expandedNodeIds.remove(node.nodeId)
            return
        }

        expandedNodeIds.insert(node.nodeId)

        guard childrenByNodeId[node.nodeId] == nil, !loadingNodeIds.contains(node.nodeId) else {
            return
        }

        loadingNodeIds.insert(node.nodeId)

        Task {
            let children = await appState.connectionManager.browseChildNodes(for: server, parentNodeId: node.nodeId)
                .filter(isVisibleInPicker)

            await MainActor.run {
                childrenByNodeId[node.nodeId] = children
                loadingNodeIds.remove(node.nodeId)
            }
        }
    }

    private func selectNode(_ node: NodeInfo) {
        guard isSubscribable(node) else { return }
        selectedNode = node
    }

    private func isVisibleInPicker(_ node: NodeInfo) -> Bool {
        isSubscribable(node) || isExpandable(node)
    }

    private func isSubscribable(_ node: NodeInfo) -> Bool {
        node.nodeClass == .variable
    }

    private func isExpandable(_ node: NodeInfo) -> Bool {
        node.nodeClass == .object || node.nodeClass == .view
    }

    private func flatten(_ nodes: [NodeInfo]) -> [NodeInfo] {
        nodes.flatMap { node in
            [node] + flatten(childrenByNodeId[node.nodeId] ?? node.children ?? [])
        }
    }
}

private struct PickerNodeTreeRow: View {
    let node: NodeInfo
    let level: Int
    let selectedNodeId: String?
    let expandedNodeIds: Set<String>
    let loadingNodeIds: Set<String>
    let childrenByNodeId: [String: [NodeInfo]]
    let onToggle: (NodeInfo) -> Void
    let onSelect: (NodeInfo) -> Void

    private var isExpanded: Bool { expandedNodeIds.contains(node.nodeId) }
    private var isLoading: Bool { loadingNodeIds.contains(node.nodeId) }
    private var isSubscribable: Bool { node.nodeClass == .variable }
    private var isExpandable: Bool { node.nodeClass == .object || node.nodeClass == .view }
    private var isSelected: Bool { selectedNodeId == node.nodeId }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
            Button(action: { isSubscribable ? onSelect(node) : onToggle(node) }) {
                HStack(spacing: DesignSystem.Spacing.xSmall) {
                    if isExpandable {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 14)
                    } else {
                        Color.clear.frame(width: 14, height: 1)
                    }

                    Image(systemName: isSubscribable ? "waveform.path.ecg" : "folder")
                        .foregroundColor(isSubscribable ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.displayName)
                            .font(DesignSystem.Typography.callout)
                            .lineLimit(1)
                        Text(node.nodeId)
                            .font(DesignSystem.Typography.monospacedCaption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else if isSubscribable {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundColor(isSelected ? DesignSystem.Colors.success : DesignSystem.Colors.primary)
                    }
                }
                .padding(DesignSystem.Spacing.xSmall)
                .background(isSelected ? DesignSystem.Colors.primary.opacity(0.12) : Color.clear)
                .cornerRadius(DesignSystem.CornerRadius.small)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, CGFloat(level) * 18)

            if isExpanded {
                ForEach((childrenByNodeId[node.nodeId] ?? node.children ?? []).filter { child in
                    child.nodeClass == .variable || child.nodeClass == .object || child.nodeClass == .view
                }) { child in
                    PickerNodeTreeRow(
                        node: child,
                        level: level + 1,
                        selectedNodeId: selectedNodeId,
                        expandedNodeIds: expandedNodeIds,
                        loadingNodeIds: loadingNodeIds,
                        childrenByNodeId: childrenByNodeId,
                        onToggle: onToggle,
                        onSelect: onSelect
                    )
                }
            }
        }
    }
}

private struct PickerNodeSearchRow: View {
    let node: NodeInfo
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignSystem.Spacing.small) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(DesignSystem.Colors.success)

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.displayName)
                        .font(DesignSystem.Typography.callout)
                    Text(node.nodeId)
                        .font(DesignSystem.Typography.monospacedCaption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.primary)
                }
            }
            .padding(DesignSystem.Spacing.small)
            .background(isSelected ? DesignSystem.Colors.primary.opacity(0.12) : DesignSystem.Colors.tertiaryBackground)
            .cornerRadius(DesignSystem.CornerRadius.small)
        }
        .buttonStyle(.plain)
    }
}
