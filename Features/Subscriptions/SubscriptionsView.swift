import SwiftUI

struct SubscriptionsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSubscription: Subscription?
    @State private var showingNewSubscription = false
    @State private var showingEditSubscription = false
    @State private var searchText = ""
    
    var filteredSubscriptions: [Subscription] {
        if searchText.isEmpty {
            return appState.subscriptions
        }
        return appState.subscriptions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Show validation alert if there are issues
            if !appState.lastSubscriptionValidationIssues.isEmpty {
                SubscriptionValidationAlert(validationIssues: appState.lastSubscriptionValidationIssues)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            Group {
            NavigationSplitView {
                SubscriptionsList(
                    subscriptions: filteredSubscriptions,
                    selectedSubscription: $selectedSubscription,
                    showingNewSubscription: $showingNewSubscription
                )
                .navigationTitle("Subscriptions")
            } detail: {
                if let subscription = selectedSubscription {
                    SubscriptionDetailView(subscription: subscription)
                } else {
                    EmptySubscriptionView(showingNewSubscription: $showingNewSubscription)
                }
            }
            }
        }
        .navigationTitle("Subscriptions")
        .searchable(text: $searchText)
        .onAppear {
            // Validate subscriptions when the view appears to ensure validation warnings are current
            appState.validateCurrentSubscriptions()
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: { showingNewSubscription = true }) {
                    Label("New Subscription", systemImage: "plus.circle.fill")
                }
                
                if selectedSubscription != nil {
                    Button(action: { showingEditSubscription = true }) {
                        Label("Edit", systemImage: "pencil.circle")
                    }
                    
                    Button(action: deleteSelectedSubscription) {
                        Label("Delete", systemImage: "trash")
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .navigationDestination(isPresented: $showingNewSubscription) {
            NewSubscriptionView()
        }
        .sheet(isPresented: $showingEditSubscription) {
            if let subscription = selectedSubscription {
                EditSubscriptionView(subscription: subscription)
            }
        }
    }
    
    private func deleteSelectedSubscription() {
        guard let subscription = selectedSubscription else { return }
        appState.deleteSubscription(subscription)
        selectedSubscription = nil
    }
}

struct SubscriptionsList: View {
    let subscriptions: [Subscription]
    @Binding var selectedSubscription: Subscription?
    @Binding var showingNewSubscription: Bool
    
    var body: some View {
        List(selection: $selectedSubscription) {
            Section("Active Subscriptions") {
                ForEach(subscriptions.filter { $0.isActive }) { subscription in
                    SubscriptionRow(subscription: subscription)
                        .tag(subscription)
                }
            }
            
            Section("Inactive Subscriptions") {
                ForEach(subscriptions.filter { !$0.isActive }) { subscription in
                    SubscriptionRow(subscription: subscription)
                        .tag(subscription)
                }
            }
            
            Section {
                Button(action: { showingNewSubscription = true }) {
                    Label("Create New Subscription", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(SidebarListStyle())
    }
}

struct SubscriptionRow: View {
    let subscription: Subscription
    
    var body: some View {
        HStack {
            Image(systemName: subscription.isActive ? "bell.fill" : "bell.slash")
                .foregroundColor(subscription.isActive ? .green : .gray)
                .font(.system(size: 14))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name)
                    .font(.system(size: 13))
                    .fontWeight(.medium)
                
                HStack(spacing: 4) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 10))
                    Text("\(subscription.monitoredItems.count) items")
                        .font(.system(size: 11))
                    
                    Text("·")
                    
                    Image(systemName: "timer")
                        .font(.system(size: 10))
                    Text("\(Int(subscription.publishingInterval))ms")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct SubscriptionDetailView: View {
    let subscription: Subscription
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            SubscriptionHeader(subscription: subscription)
            
            Picker("", selection: $selectedTab) {
                Text("Monitored Items").tag(0)
                Text("Configuration").tag(1)
                Text("Statistics").tag(2)
                Text("Events").tag(3)
            }
            .pickerStyle(.segmented)
            .padding()
            
            TabView(selection: $selectedTab) {
                MonitoredItemsList(subscription: subscription)
                    .tag(0)
                
                SubscriptionConfiguration(subscription: subscription)
                    .tag(1)
                
                SubscriptionStatistics(subscription: subscription)
                    .tag(2)
                
                SubscriptionEvents()
                    .tag(3)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
        }
    }
}

struct SubscriptionHeader: View {
    let subscription: Subscription
    @State private var isActive: Bool
    
    init(subscription: Subscription) {
        self.subscription = subscription
        self._isActive = State(initialValue: subscription.isActive)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(subscription.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                HStack {
                    Label("\(subscription.monitoredItems.count) items", systemImage: "tag.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("·")
                        .foregroundColor(.secondary)
                    
                    Label("\(Int(subscription.publishingInterval))ms interval", systemImage: "timer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Toggle(isOn: $isActive) {
                Text(isActive ? "Active" : "Inactive")
                    .font(.caption)
            }
            .toggleStyle(.switch)
        }
        .padding()
        .background(Color.secondarySystemBackground)
    }
}

struct MonitoredItemsList: View {
    let subscription: Subscription
    @EnvironmentObject var appState: AppState
    @State private var selectedItems = Set<UUID>()
    @State private var showingDeleteConfirmation = false
    @State private var itemToDelete: MonitoredItem?
    @State private var showingSingleItemDeleteConfirmation = false
    
    // Create a computed property to get the current items from appState
    var currentSubscription: Subscription? {
        appState.subscriptions.first { $0.id == subscription.id }
    }
    
    var body: some View {
        VStack {
            #if os(macOS)
            Table(currentSubscription?.monitoredItems ?? subscription.monitoredItems, selection: $selectedItems) {
                TableColumn("Name", value: \.displayName)
                    .width(min: 150)
                TableColumn("Node ID", value: \.nodeId)
                    .width(min: 200)
                TableColumn("Value") { item in
                    Text(item.currentValue ?? "N/A")
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 100)
                TableColumn("Last Update") { item in
                    if let timestamp = item.timestamp {
                        Text(timestamp, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Never")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .width(min: 80)
                TableColumn("Quality") { item in
                    HStack {
                        Circle()
                            .fill(item.quality.color)
                            .frame(width: 8, height: 8)
                        Text(item.quality.rawValue)
                            .font(.caption)
                    }
                }
                .width(80)
                TableColumn("Sampling") { item in
                    Text("\(Int(item.samplingInterval))ms")
                        .font(.caption)
                }
                .width(80)
                TableColumn("Actions") { item in
                    HStack(spacing: 8) {
                        Button(action: { 
                            itemToDelete = item
                            showingSingleItemDeleteConfirmation = true 
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .help("Delete this item")
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { refreshItem(item) }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.blue)
                                .help("Refresh value")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .width(80)
            }
            
            if !selectedItems.isEmpty {
                HStack {
                    Button(action: { showingDeleteConfirmation = true }) {
                        Label("Delete Selected (\(selectedItems.count))", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
                .padding()
            }
            #else
            List(selection: $selectedItems) {
                ForEach(currentSubscription?.monitoredItems ?? subscription.monitoredItems) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.displayName)
                                .font(.headline)
                            Text(item.nodeId)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(item.currentValue ?? "N/A")
                                .font(.system(.body, design: .monospaced))
                            if let timestamp = item.timestamp {
                                Text(timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Circle()
                                    .fill(item.quality.color)
                                    .frame(width: 8, height: 8)
                                Text(item.quality.rawValue)
                                    .font(.caption)
                            }
                        }
                        
                        // Delete button
                        Button(action: { 
                            itemToDelete = item
                            showingSingleItemDeleteConfirmation = true 
                        }) {
                            Image(systemName: "trash.circle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 22))
                        }
                        .buttonStyle(.plain)
                    }
                    .tag(item.id)
                }
            }
            #endif
        }
        .alert("Delete Items", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSelectedItems()
            }
        } message: {
            Text("Are you sure you want to delete \(selectedItems.count) monitored item(s)?")
        }
        .alert("Delete Item", isPresented: $showingSingleItemDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    deleteSingleItem(item)
                }
            }
        } message: {
            if let item = itemToDelete {
                Text("Delete '\(item.displayName)' from this subscription?")
            }
        }
    }
    
    private func deleteSelectedItems() {
        // Get current subscription from appState
        guard let currentSub = appState.subscriptions.first(where: { $0.id == subscription.id }) else { return }
        
        // Get the node IDs of items being removed for validation cleanup
        let nodeIdsToRemove = currentSub.monitoredItems
            .filter { selectedItems.contains($0.id) }
            .map { $0.nodeId }
        
        // Create updated subscription without selected items
        var updatedSubscription = currentSub
        updatedSubscription.monitoredItems.removeAll { selectedItems.contains($0.id) }
        
        // Save the updated subscription - this will trigger UI refresh
        appState.saveSubscription(updatedSubscription)
        
        // Clear validation issues for the removed items
        appState.lastSubscriptionValidationIssues.removeAll { nodeIdsToRemove.contains($0.nodeId) }
        
        // Clear selection
        selectedItems.removeAll()
    }
    
    private func deleteSingleItem(_ item: MonitoredItem) {
        // Get current subscription from appState
        guard let currentSub = appState.subscriptions.first(where: { $0.id == subscription.id }) else { return }
        
        // Create updated subscription without the item
        var updatedSubscription = currentSub
        updatedSubscription.monitoredItems.removeAll { $0.id == item.id }
        
        // Save the updated subscription - this will trigger immediate UI refresh
        appState.saveSubscription(updatedSubscription)
        
        // Clear validation issues for the removed item
        appState.lastSubscriptionValidationIssues.removeAll { $0.nodeId == item.nodeId }
        
        // Clear the item to delete
        itemToDelete = nil
    }
    
    private func refreshItem(_ item: MonitoredItem) {
        // Refresh the value from the server
        Task {
            if let server = appState.servers.first(where: { $0.id == subscription.serverId }) {
                if let newValue = await appState.connectionManager.readNodeValue(for: server, nodeId: item.nodeId) {
                    // Update the monitored item value
                    appState.updateMonitoredItemValue(
                        nodeId: item.nodeId, 
                        value: newValue, 
                        quality: .good
                    )
                }
            }
        }
    }
}

struct SubscriptionConfiguration: View {
    @EnvironmentObject var appState: AppState
    let subscription: Subscription
    @State private var publishingInterval: Double
    @State private var priority: Int
    @State private var maxNotificationsPerPublish = 100
    @State private var lifetimeCount = 10000
    @State private var maxKeepAliveCount = 3000
    @State private var samplingPreset: SamplingPreset = .standard
    
    init(subscription: Subscription) {
        self.subscription = subscription
        self._publishingInterval = State(initialValue: subscription.publishingInterval)
        self._priority = State(initialValue: subscription.priority)
    }
    
    var body: some View {
        Form {
            Section("Publishing Parameters") {
                HStack {
                    Text("Publishing Interval")
                    Spacer()
                    TextField("ms", value: $publishingInterval, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Text("ms")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Priority")
                    Spacer()
                    Stepper(value: $priority, in: 0...255) {
                        Text("\(priority)")
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                
                HStack {
                    Text("Max Notifications per Publish")
                    Spacer()
                    TextField("", value: $maxNotificationsPerPublish, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }

            Section("Monitoring Defaults") {
                Picker("Sampling Preset", selection: $samplingPreset) {
                    ForEach(SamplingPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                Button("Apply Preset to Items") {
                    applySamplingPreset()
                }
                .disabled(subscription.monitoredItems.isEmpty)
            }
            
            Section("Lifetime Management") {
                HStack {
                    Text("Lifetime Count")
                    Spacer()
                    TextField("", value: $lifetimeCount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                
                HStack {
                    Text("Max Keep-Alive Count")
                    Spacer()
                    TextField("", value: $maxKeepAliveCount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }
            
            Section {
                HStack {
                    Button("Reset to Defaults") {
                        publishingInterval = 1000
                        priority = 1
                        maxNotificationsPerPublish = 100
                        lifetimeCount = 10000
                        maxKeepAliveCount = 3000
                        samplingPreset = .standard
                    }
                    
                    Spacer()
                    
                    Button("Apply Changes") {}
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
    }

    private func applySamplingPreset() {
        guard let currentSub = appState.subscriptions.first(where: { $0.id == subscription.id }) else { return }

        let interval = samplingPreset == .custom ? 1000.0 : samplingPreset.interval
        let updatedItems = currentSub.monitoredItems.map { item in
            MonitoredItem(
                id: item.id,
                nodeId: item.nodeId,
                displayName: item.displayName,
                samplingInterval: interval,
                samplingPreset: samplingPreset,
                deadbandType: item.deadbandType,
                deadbandValue: item.deadbandValue,
                queueSize: item.queueSize,
                discardOldest: item.discardOldest,
                currentValue: item.currentValue,
                timestamp: item.timestamp,
                quality: item.quality
            )
        }

        let updatedSubscription = Subscription(
            id: currentSub.id,
            name: currentSub.name,
            serverId: currentSub.serverId,
            publishingInterval: currentSub.publishingInterval,
            priority: currentSub.priority,
            isActive: currentSub.isActive,
            monitoredItems: updatedItems
        )

        appState.saveSubscription(updatedSubscription)
    }
}

struct SubscriptionStatistics: View {
    let subscription: Subscription
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StatisticsCard(
                    title: "Publishing",
                    statistics: [
                        ("Publish Requests", "1,245"),
                        ("Data Change Notifications", "15,432"),
                        ("Event Notifications", "0"),
                        ("Keep-Alive Messages", "89")
                    ]
                )
                
                StatisticsCard(
                    title: "Performance",
                    statistics: [
                        ("Average Latency", "12 ms"),
                        ("Max Latency", "145 ms"),
                        ("Messages/sec", "45"),
                        ("Data Rate", "2.3 KB/s")
                    ]
                )
                
                StatisticsCard(
                    title: "Errors",
                    statistics: [
                        ("Timeouts", "0"),
                        ("Bad Requests", "0"),
                        ("Republish Requests", "2"),
                        ("Sequence Errors", "0")
                    ]
                )
            }
            .padding()
        }
    }
}

struct StatisticsCard: View {
    let title: String
    let statistics: [(String, String)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            Divider()
            
            ForEach(statistics, id: \.0) { stat in
                HStack {
                    Text(stat.0)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(stat.1)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondarySystemGroupedBackground)
        )
    }
}

struct SubscriptionEvents: View {
    @State private var events: [EventLog] = []

    struct EventLog: Identifiable {
        let id = UUID()
        let timestamp: Date
        let type: String
        let message: String
        let severity: Severity

        enum Severity {
            case info, warning, error

            var color: Color {
                switch self {
                case .info: return .blue
                case .warning: return .orange
                case .error: return .red
                }
            }

            var systemImage: String {
                switch self {
                case .info: return "info.circle"
                case .warning: return "exclamationmark.triangle"
                case .error: return "xmark.circle"
                }
            }
        }
    }

    var body: some View {
        Group {
            if events.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Events")
                        .font(.headline)

                    Text("Subscription events will appear here when the subscription is active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(events) { event in
                    HStack {
                        Image(systemName: event.severity.systemImage)
                            .foregroundColor(event.severity.color)
                            .font(.system(size: 14))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(event.type)
                                    .font(.caption)
                                    .fontWeight(.medium)

                                Text(event.timestamp, format: .dateTime.hour().minute().second())
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Text(event.message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

struct EmptySubscriptionView: View {
    @Binding var showingNewSubscription: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge")
                .font(.system(size: 72))
                .foregroundColor(.secondary)
                .symbolEffect(.pulse)
            
            Text("No Subscription Selected")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Select a subscription to view details or create a new one")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { showingNewSubscription = true }) {
                Label("Create Subscription", systemImage: "plus.circle.fill")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NewSubscriptionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @State private var name = ""
    @State private var selectedServer: OPCUAServer?
    @State private var publishingInterval = "1000"
    @State private var priority = 1
    @State private var maxNotificationsPerPublish = 100
    @State private var lifetimeCount = 10000
    @State private var isActive = true
    
    // Filter to show only connected servers
    var connectedServers: [OPCUAServer] {
        appState.servers.filter { server in
            appState.connectionManager.getConnectionStatus(for: server) == .connected
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Create a subscription to monitor OPC UA variables in real-time.")
                            .font(OPCTheme.Typography.callout)
                            .foregroundColor(OPCTheme.Colors.text)
                        Text("Fields are grouped. Scroll for advanced settings.")
                            .font(OPCTheme.Typography.caption2)
                            .foregroundColor(OPCTheme.Colors.secondaryText)
                    }
                    .padding(.vertical, 4)
                }

                Section("Basics") {
                    TextField("Subscription Name", text: $name)

                    Picker("Server", selection: $selectedServer) {
                        if connectedServers.isEmpty {
                            Text("No connected servers").tag(nil as OPCUAServer?)
                        } else {
                            Text("Select Server").tag(nil as OPCUAServer?)
                            ForEach(connectedServers) { server in
                                Text(server.name).tag(server as OPCUAServer?)
                            }
                        }
                    }
                    .disabled(connectedServers.isEmpty)

                    if connectedServers.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(OPCTheme.Colors.warning)
                            Text("Connect to a server first from the Servers tab.")
                                .font(OPCTheme.Typography.caption2)
                                .foregroundColor(OPCTheme.Colors.secondaryText)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Publishing Interval")
                        Spacer()
                        TextField("1000", text: $publishingInterval)
                            .frame(width: 90)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Text("ms")
                            .foregroundColor(OPCTheme.Colors.secondaryText)
                    }

                    HStack(spacing: 8) {
                        intervalChip("250")
                        intervalChip("500")
                        intervalChip("1000")
                        intervalChip("2000")
                    }

                    Stepper(value: $priority, in: 0...255) {
                        Text("Priority")
                    }

                    Toggle("Start Active", isOn: $isActive)
                } header: {
                    Text("Publishing")
                } footer: {
                    Text("Lower intervals deliver faster updates but increase network load.")
                }

                Section("Advanced") {
                    Stepper(value: $maxNotificationsPerPublish, in: 1...1000) {
                        Text("Max Notifications")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Subscription")
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
                    Button("Create") {
                        createSubscription()
                        dismiss()
                    }
                    .disabled(name.isEmpty || selectedServer == nil || connectedServers.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
        #endif
    }

    private func intervalChip(_ value: String) -> some View {
        Button {
            publishingInterval = value
        } label: {
            Text("\(value) ms")
                .font(OPCTheme.Typography.caption2)
                .foregroundColor(publishingInterval == value ? .white : OPCTheme.Colors.text)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    Capsule()
                        .fill(publishingInterval == value ? OPCTheme.Colors.primary : OPCTheme.Colors.secondaryBackground)
                )
        }
        .buttonStyle(.plain)
    }
    
    private func createSubscription() {
        guard let server = selectedServer,
              let interval = Double(publishingInterval) else { return }
        
        let newSubscription = Subscription(
            name: name,
            serverId: server.id,
            publishingInterval: interval,
            priority: priority,
            isActive: isActive,
            monitoredItems: []
        )
        
        // Use AppState's persistence method
        appState.saveSubscription(newSubscription)
        print("Created subscription: \(name) for server: \(server.name)")
    }
}
