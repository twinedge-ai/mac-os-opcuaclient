import SwiftUI

struct EditSubscriptionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    let subscription: Subscription
    
    @State private var name: String
    @State private var publishingInterval: String
    @State private var priority: Int
    @State private var isActive: Bool
    @State private var showingDeleteConfirmation = false
    @State private var showingAddNodeSheet = false
    @State private var selectedItems = Set<UUID>()
    
    init(subscription: Subscription) {
        self.subscription = subscription
        self._name = State(initialValue: subscription.name)
        self._publishingInterval = State(initialValue: String(Int(subscription.publishingInterval)))
        self._priority = State(initialValue: subscription.priority)
        self._isActive = State(initialValue: subscription.isActive)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Edit Subscription")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("Modify subscription settings and monitored items")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                }
                
                Form {
                    // Basic Information
                    Section {
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            TextField("Subscription name", text: $name)
                        }
                        .padding(.vertical, 4)
                        
                        HStack {
                            Image(systemName: "server.rack")
                                .foregroundColor(.green)
                                .frame(width: 24)
                            Text("Server")
                            Spacer()
                            Text(getServerName())
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        
                    } header: {
                        Label("Basic Information", systemImage: "info.circle")
                    }
                    
                    // Publishing Configuration
                    Section {
                        HStack {
                            Image(systemName: "timer")
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            Text("Publishing Interval")
                            Spacer()
                            TextField("1000", text: $publishingInterval)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .multilineTextAlignment(.trailing)
                            Text("ms")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        
                        HStack {
                            Image(systemName: "flag.fill")
                                .foregroundColor(.purple)
                                .frame(width: 24)
                            Text("Priority")
                            Spacer()
                            Stepper(value: $priority, in: 0...255) {
                                Text("\(priority)")
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .padding(.vertical, 4)
                        
                        Toggle(isOn: $isActive) {
                            HStack {
                                Image(systemName: isActive ? "play.circle.fill" : "pause.circle")
                                    .foregroundColor(isActive ? .green : .orange)
                                    .frame(width: 24)
                                Text("Active")
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Label("Publishing Configuration", systemImage: "gear")
                    }
                    
                    // Monitored Items
                    Section {
                        if subscription.monitoredItems.isEmpty {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Text("No monitored items")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Add Items") {
                                    showingAddNodeSheet = true
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 8)
                        } else {
                            ForEach(subscription.monitoredItems) { item in
                                MonitoredItemRow(
                                    item: item,
                                    isSelected: selectedItems.contains(item.id),
                                    onToggle: { toggleSelection(item.id) }
                                )
                            }
                            
                            HStack {
                                Button(action: deleteSelectedItems) {
                                    Label("Delete Selected", systemImage: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .disabled(selectedItems.isEmpty)
                                
                                Spacer()
                                
                                Button("Add Items") {
                                    showingAddNodeSheet = true
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 8)
                        }
                    } header: {
                        HStack {
                            Label("Monitored Items (\(subscription.monitoredItems.count))", systemImage: "list.bullet")
                            Spacer()
                            if !subscription.monitoredItems.isEmpty {
                                Button(selectedItems.count == subscription.monitoredItems.count ? "Deselect All" : "Select All") {
                                    toggleSelectAll()
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                            }
                        }
                    }
                    
                    // Delete Subscription
                    Section {
                        Button(action: { showingDeleteConfirmation = true }) {
                            HStack {
                                Image(systemName: "trash.fill")
                                    .foregroundColor(.white)
                                Text("Delete Subscription")
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Edit Subscription")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .alert("Delete Subscription", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteSubscription()
                }
            } message: {
                Text("Are you sure you want to delete this subscription? This will also remove all monitored items.")
            }
            .sheet(isPresented: $showingAddNodeSheet) {
                AddNodesToSubscriptionView(subscription: subscription)
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }
    
    private func getServerName() -> String {
        if let server = appState.servers.first(where: { $0.id == subscription.serverId }) {
            return server.name
        }
        return "Unknown Server"
    }
    
    private func toggleSelection(_ itemId: UUID) {
        if selectedItems.contains(itemId) {
            selectedItems.remove(itemId)
        } else {
            selectedItems.insert(itemId)
        }
    }
    
    private func toggleSelectAll() {
        if selectedItems.count == subscription.monitoredItems.count {
            selectedItems.removeAll()
        } else {
            selectedItems = Set(subscription.monitoredItems.map { $0.id })
        }
    }
    
    private func deleteSelectedItems() {
        // Create updated subscription without selected items
        var updatedSubscription = subscription
        updatedSubscription.monitoredItems.removeAll { selectedItems.contains($0.id) }
        
        // Save the updated subscription
        appState.saveSubscription(updatedSubscription)
        
        // Clear selection
        selectedItems.removeAll()
    }
    
    private func saveChanges() {
        guard let interval = Double(publishingInterval) else { return }
        
        var updatedSubscription = subscription
        updatedSubscription.name = name
        updatedSubscription.publishingInterval = interval
        updatedSubscription.priority = priority
        updatedSubscription.isActive = isActive
        
        // Save using persistence
        appState.saveSubscription(updatedSubscription)
    }
    
    private func deleteSubscription() {
        appState.deleteSubscription(subscription)
        dismiss()
    }
}

struct MonitoredItemRow: View {
    let item: MonitoredItem
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 13))
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Text(item.nodeId)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    if let value = item.currentValue {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(value)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(item.quality.color)
                            .frame(width: 6, height: 6)
                        Text(item.quality.rawValue)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddNodesToSubscriptionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    let subscription: Subscription
    
    @State private var searchText = ""
    @State private var selectedNodes = Set<String>()
    @State private var availableNodes: [NodeInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var samplingPreset: SamplingPreset = .standard
    @State private var deadbandType: DeadbandType = .none
    @State private var deadbandValue = "0"

    private var filteredNodes: [NodeInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return availableNodes }
        return availableNodes.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            $0.nodeId.localizedCaseInsensitiveContains(query)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                Form {
                    Section("Monitoring Defaults") {
                        Picker("Sampling Preset", selection: $samplingPreset) {
                            ForEach(SamplingPreset.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("Deadband", selection: $deadbandType) {
                            ForEach(DeadbandType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)

                        if deadbandType != .none {
                            HStack {
                                Text(deadbandType == .percent ? "Deadband (%)" : "Deadband Value")
                                Spacer()
                                TextField("0", text: $deadbandValue)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                            }
                        }
                    }
                }

                if isLoading {
                    ProgressView("Loading available nodes...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "network.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Address Space Unavailable")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if availableNodes.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No nodes available")
                            .font(.headline)
                        Text("Browse the address space first to see available nodes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredNodes, id: \.nodeId) { node in
                        HStack {
                            Button(action: { toggleNode(node) }) {
                                Image(systemName: selectedNodes.contains(node.nodeId) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedNodes.contains(node.nodeId) ? .blue : .gray)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading) {
                                Text(node.displayName)
                                    .font(.system(size: 13))
                                Text(node.nodeId)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if let dataType = node.dataType {
                                Text(dataType)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .searchable(text: $searchText, prompt: "Search nodes...")
                }
            }
            .navigationTitle("Add Nodes to Subscription")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedNodes.count))") {
                        addSelectedNodes()
                        dismiss()
                    }
                    .disabled(selectedNodes.isEmpty)
                }
            }
        }
        .onAppear {
            loadAvailableNodes()
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 500)
        #endif
    }
    
    private func toggleNode(_ node: NodeInfo) {
        if selectedNodes.contains(node.nodeId) {
            selectedNodes.remove(node.nodeId)
        } else {
            selectedNodes.insert(node.nodeId)
        }
    }
    
    private func loadAvailableNodes() {
        guard let server = appState.servers.first(where: { $0.id == subscription.serverId }) else {
            errorMessage = "This subscription no longer has a matching server profile."
            isLoading = false
            return
        }

        guard appState.connectionManager.isConnected(to: server) else {
            errorMessage = "Connect to \(server.name) before browsing nodes."
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            let rootNodes = await appState.connectionManager.browseAddressSpace(for: server, maxDepth: 2)
            let nodes = flatten(rootNodes)
                .filter { $0.nodeClass == .variable }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            await MainActor.run {
                availableNodes = nodes
                isLoading = false
                if nodes.isEmpty {
                    errorMessage = nil
                }
            }
        }
    }

    private func flatten(_ nodes: [NodeInfo]) -> [NodeInfo] {
        nodes.flatMap { node in
            [node] + flatten(node.children ?? [])
        }
    }
    
    private func addSelectedNodes() {
        let deadband = Double(deadbandValue) ?? 0
        let interval = samplingPreset == .custom ? 1000.0 : samplingPreset.interval

        for nodeId in selectedNodes {
            if let node = availableNodes.first(where: { $0.nodeId == nodeId }) {
                let newItem = MonitoredItem(
                    nodeId: node.nodeId,
                    displayName: node.displayName,
                    samplingInterval: interval,
                    samplingPreset: samplingPreset,
                    deadbandType: deadbandType,
                    deadbandValue: deadband,
                    queueSize: 10,
                    discardOldest: true,
                    currentValue: node.value,
                    timestamp: Date(),
                    quality: node.quality
                )
                
                appState.addMonitoredItem(newItem, to: subscription.id)
            }
        }
    }
}
