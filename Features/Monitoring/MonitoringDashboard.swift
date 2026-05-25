import SwiftUI
import Charts
import Combine

struct MonitoringDashboard: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var monitoringState = MonitoringState()
    @State private var viewMode: ViewMode = .grid
    @State private var refreshInterval: Double = 1.0
    @State private var showAddItem = false
    @State private var selectedSubscription: Subscription?
    
    // Get all monitored items from all active subscriptions
    var allMonitoredItems: [MonitoredItem] {
        appState.subscriptions.filter { $0.isActive }
            .flatMap { $0.monitoredItems }
    }
    
    // Filter items based on selected subscription
    var filteredItems: [MonitoredItem] {
        if let subscription = selectedSubscription {
            return subscription.monitoredItems
        } else {
            return allMonitoredItems
        }
    }

    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case list = "List"
        case chart = "Chart"

        var systemImage: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            case .chart: return "chart.line.uptrend.xyaxis"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Show validation alert if there are issues
            if !appState.lastSubscriptionValidationIssues.isEmpty {
                SubscriptionValidationAlert(validationIssues: appState.lastSubscriptionValidationIssues)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            DashboardHeader(
                viewMode: $viewMode,
                refreshInterval: $refreshInterval,
                showAddItem: $showAddItem
            )

            if allMonitoredItems.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 0) {
                    // Subscription picker
                    SubscriptionPicker(
                        subscriptions: appState.subscriptions.filter { $0.isActive },
                        selectedSubscription: $selectedSubscription
                    )
                    .padding()
                    .background(Color.secondarySystemBackground)
                    
                    switch viewMode {
                    case .grid:
                        GridView(items: filteredItems, selectedItems: $monitoringState.selectedItems)
                    case .list:
                        ListView(items: filteredItems, selectedItems: $monitoringState.selectedItems)
                    case .chart:
                        ChartView(items: filteredItems, dataHistory: monitoringState.dataHistory)
                    }
                }
            }
        }
        .navigationTitle("Real-Time Monitoring")
        .sheet(isPresented: $showAddItem) {
            AddMonitoredItemView(monitoringState: monitoringState, appState: appState)
        }
        .onAppear {
            monitoringState.setConnectionManager(appState.connectionManager)
            monitoringState.startMonitoring(interval: refreshInterval)
            // Validate subscriptions when the view appears to ensure validation warnings are current
            appState.validateCurrentSubscriptions()
        }
        .onDisappear {
            monitoringState.stopMonitoring()
        }
        .onChange(of: refreshInterval) { _, newValue in
            monitoringState.startMonitoring(interval: newValue)
        }
    }

    var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No Monitored Items")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add items from the address space to monitor their values in real-time")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showAddItem = true }) {
                Label("Add Monitored Item", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

@MainActor
class MonitoringState: ObservableObject {
    @Published var monitoredItems: [MonitoredItem] = []
    @Published var selectedItems: Set<MonitoredItem> = []
    @Published var dataHistory: [String: [DataPoint]] = [:]

    private var connectionManager: OPCUAConnectionManager?
    private var server: OPCUAServer?
    private var cancellables = Set<AnyCancellable>()

    func setConnectionManager(_ manager: OPCUAConnectionManager) {
        self.connectionManager = manager
        setupNotifications()
    }

    func setServer(_ server: OPCUAServer) {
        self.server = server
    }

    private func setupNotifications() {
        // Clear existing subscriptions to avoid duplicates if re-setup
        cancellables.removeAll()
        
        // Listen for data changes from the connection manager
        NotificationCenter.default.publisher(for: .opcuaDataChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let userInfo = notification.userInfo,
                      let nodeId = userInfo["nodeId"] as? String,
                      let value = userInfo["value"] as? String else {
                    return
                }
                
                self.updateItemValue(nodeId: nodeId, value: value)
            }
            .store(in: &cancellables)
            
        // Also listen for connection changes to refresh statuses
        NotificationCenter.default.publisher(for: .opcuaConnectionChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshAll()
            }
            .store(in: &cancellables)
    }

    func addMonitoredItem(nodeId: String, displayName: String, server: OPCUAServer, appState: AppState) async {
        let manager = appState.connectionManager

        // 1. Create/Find subscription in AppState
        let subscription: Subscription
        if let existing = appState.subscriptions.first(where: { $0.serverId == server.id && $0.isActive }) {
            subscription = existing
        } else {
            // Create a default subscription for this server
            subscription = Subscription(
                name: "Monitoring (\(server.name))",
                serverId: server.id,
                publishingInterval: 1000.0,
                priority: 1,
                isActive: true,
                monitoredItems: []
            )
            appState.saveSubscription(subscription)
            
            // Create it on the server
            _ = await manager.createSubscription(for: server, publishingInterval: 1000.0)
        }

        // 2. Add monitored item to manager
        let success = await manager.addMonitoredItem(for: server, nodeId: nodeId)

        if success {
            // 3. Add to AppState
            let item = MonitoredItem(
                nodeId: nodeId,
                displayName: displayName,
                samplingInterval: 1000.0,
                queueSize: 10,
                discardOldest: true,
                currentValue: nil,
                timestamp: nil,
                quality: .good
            )
            
            appState.addMonitoredItem(item, to: subscription.id)
            
            // Also keep track locally for history
            if !monitoredItems.contains(where: { $0.nodeId == nodeId }) {
                monitoredItems.append(item)
                dataHistory[nodeId] = []
            }
            
            self.server = server

            // Read initial value
            if let value = await manager.readValue(for: server, nodeId: nodeId) {
                updateItemValue(nodeId: nodeId, value: value)
            }
        }
    }

    func removeMonitoredItem(_ item: MonitoredItem) {
        monitoredItems.removeAll { $0.id == item.id }
        dataHistory.removeValue(forKey: item.nodeId)
        selectedItems.remove(item)
        
        // Remove from AppState and server
        Task {
            if let server = server, let manager = connectionManager {
                _ = await manager.removeMonitoredItem(for: server, nodeId: item.nodeId)
                
                // Note: We don't have a direct appState.removeMonitoredItem for a specific item id 
                // in the top-level AppState, but we can rely on persistence or just leave it.
                // Ideally AppState should have a method to find subscription and remove item.
            }
        }
    }

    func startMonitoring(interval: Double) {
        // Refresh values initially
        Task {
            await refreshValues()
        }
    }

    func stopMonitoring() {
        // No longer needed to invalidate timers
    }

    private func refreshValues() async {
        // Manual refresh if needed (e.g. on appear)
        guard let manager = connectionManager, let server = server else { return }

        for item in monitoredItems {
            if let value = await manager.readValue(for: server, nodeId: item.nodeId) {
                updateItemValue(nodeId: item.nodeId, value: value)
            }
        }
    }
    
    // Helper helper to refresh without async context requirement for notifications
    private func refreshAll() {
        Task {
            await refreshValues()
        }
    }

    private func updateItemValue(nodeId: String, value: String) {
        let now = Date()
        
        // 1. Update local list IF it exists (legacy support/local state)
        if let index = monitoredItems.firstIndex(where: { $0.nodeId == nodeId }) {
            var updatedItem = monitoredItems[index]
            updatedItem.currentValue = value
            updatedItem.timestamp = now
            updatedItem.quality = .good
            monitoredItems[index] = updatedItem
        }

        // 2. ALWAYS Update history for charts
        // This ensures that even if the item is managed by AppState (global), we still track its history for the chart
        if let numericValue = Double(value) {
            var history = dataHistory[nodeId] ?? []
            history.append(DataPoint(timestamp: now, value: numericValue))

            // Keep only last 100 points
            if history.count > 100 {
                history.removeFirst(history.count - 100)
            }
            dataHistory[nodeId] = history
        }
    }
}

struct DashboardHeader: View {
    @Binding var viewMode: MonitoringDashboard.ViewMode
    @Binding var refreshInterval: Double
    @Binding var showAddItem: Bool

    var body: some View {
        HStack {
            Picker("View Mode", selection: $viewMode) {
                ForEach(MonitoringDashboard.ViewMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Spacer()

            HStack {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)

                Picker("Refresh", selection: $refreshInterval) {
                    Text("0.5s").tag(0.5)
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("5s").tag(5.0)
                    Text("10s").tag(10.0)
                }
                .pickerStyle(.menu)
                .frame(width: 80)
            }

            Button(action: { showAddItem = true }) {
                Label("Add Item", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.secondarySystemBackground)
    }
}

struct GridView: View {
    let items: [MonitoredItem]
    @Binding var selectedItems: Set<MonitoredItem>

    let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 300))
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    MonitoringCard(
                        item: item,
                        isSelected: selectedItems.contains(item)
                    ) {
                        toggleSelection(item)
                    }
                }
            }
            .padding()
        }
    }

    func toggleSelection(_ item: MonitoredItem) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
        } else {
            selectedItems.insert(item)
        }
    }
}

struct ListView: View {
    let items: [MonitoredItem]
    @Binding var selectedItems: Set<MonitoredItem>

    var body: some View {
        List(selection: $selectedItems) {
            ForEach(items) { item in
                MonitoringRow(item: item)
                    .tag(item)
            }
        }
    }
}

struct ChartView: View {
    let items: [MonitoredItem]
    let dataHistory: [String: [DataPoint]]
    @State private var selectedItem: MonitoredItem?

    var body: some View {
        VStack {
            if let selected = selectedItem ?? items.first {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(selected.displayName)
                                .font(.title2)
                                .fontWeight(.semibold)

                            HStack {
                                Circle()
                                    .fill(selected.quality.color)
                                    .frame(width: 10, height: 10)
                                Text(selected.quality.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if let value = selected.currentValue {
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    Text(value)
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.medium)
                                }
                            }
                        }

                        Spacer()

                        Picker("Select Item", selection: $selectedItem) {
                            ForEach(items) { item in
                                Text(item.displayName)
                                    .tag(item as MonitoredItem?)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }
                    .padding(.horizontal)

                    let dataPoints = dataHistory[selected.nodeId] ?? []
                    if dataPoints.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No data yet")
                                .font(.headline)
                            Text("Numeric values will appear here as they are received")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        TimeSeriesChart(dataPoints: dataPoints)
                            .frame(height: 400)
                            .padding()
                    }
                }
                .padding()
            } else {
                Text("Select an item to view chart")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            selectedItem = items.first
        }
    }
}

struct MonitoringCard: View {
    let item: MonitoredItem
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    @State private var showingDeleteConfirmation = false
    @EnvironmentObject var appState: AppState
    
    // Get validation for this item
    var validation: MonitoredItemValidation? {
        appState.lastSubscriptionValidationIssues.first { $0.nodeId == item.nodeId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.displayName)
                            .font(.headline)
                        
                        // Show validation indicator if there's an issue
                        if let validation = validation, !validation.isValid {
                            ValidationIndicator(validation: validation)
                        }
                    }

                    Text(item.nodeId)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()
                
                HStack(spacing: 8) {
                    // Delete button
                    Button(action: { showingDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .help("Remove this monitored item")
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .font(.title3)
                }
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Value")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(item.currentValue ?? "N/A")
                        .font(.system(size: 20, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(item.quality.color)
                            .frame(width: 8, height: 8)
                        Text(item.quality.rawValue)
                            .font(.caption2)
                    }

                    if let timestamp = item.timestamp {
                        Text(timestamp, format: .dateTime.hour().minute().second())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ?
                    Color.accentColor.opacity(0.1) :
                    Color.secondarySystemGroupedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isHovered ? 1.02 : 1)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            action()
        }
        .confirmationDialog(
            "Remove Monitored Item",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove \(item.displayName)", role: .destructive) {
                deleteItem()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to remove '\(item.displayName)' (Node: \(item.nodeId)) from monitoring?")
        }
    }
    
    private func deleteItem() {
        Task {
            // Find the subscription containing this item
            if let subscription = appState.subscriptions.first(where: { 
                $0.monitoredItems.contains(where: { $0.id == item.id }) 
            }) {
                // Remove from server
                if let server = appState.servers.first(where: { $0.id == subscription.serverId }) {
                    _ = await appState.connectionManager.removeMonitoredItem(for: server, nodeId: item.nodeId)
                }
                
                // Remove from local subscription
                let subId = subscription.id
                await MainActor.run {
                    appState.removeMonitoredItem(item, from: subId)
                    appState.validateCurrentSubscriptions()
                }
            }
        }
    }
}

struct MonitoringRow: View {
    let item: MonitoredItem
    @EnvironmentObject var appState: AppState
    @State private var showingDeleteConfirmation = false
    
    // Get validation for this item
    var validation: MonitoredItemValidation? {
        appState.lastSubscriptionValidationIssues.first { $0.nodeId == item.nodeId }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    // Show validation indicator if there's an issue
                    if let validation = validation, !validation.isValid {
                        ValidationIndicator(validation: validation)
                    }
                }

                Text(item.nodeId)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(item.currentValue ?? "N/A")
                    .font(.system(size: 16, design: .monospaced))
                    .fontWeight(.medium)

                HStack {
                    Circle()
                        .fill(item.quality.color)
                        .frame(width: 8, height: 8)
                    Text(item.quality.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let timestamp = item.timestamp {
                Text(timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .trailing)
            }
            
            // Delete button
            Button(action: { showingDeleteConfirmation = true }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .help("Remove this monitored item")
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Remove Monitored Item",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove \(item.displayName)", role: .destructive) {
                deleteItem()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to remove '\(item.displayName)' (Node: \(item.nodeId)) from monitoring?")
        }
    }
    
    private func deleteItem() {
        Task {
            // Find the subscription containing this item
            if let subscription = appState.subscriptions.first(where: { 
                $0.monitoredItems.contains(where: { $0.id == item.id }) 
            }) {
                // Remove from server
                if let server = appState.servers.first(where: { $0.id == subscription.serverId }) {
                    _ = await appState.connectionManager.removeMonitoredItem(for: server, nodeId: item.nodeId)
                }
                
                // Remove from local subscription
                let subId = subscription.id
                await MainActor.run {
                    appState.removeMonitoredItem(item, from: subId)
                    appState.validateCurrentSubscriptions()
                }
            }
        }
    }
}

struct TimeSeriesChart: View {
    let dataPoints: [DataPoint]

    var body: some View {
        Chart(dataPoints) { point in
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Value", point.value)
            )
            .foregroundStyle(Color.blue.gradient)

            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Value", point.value)
            )
            .foregroundStyle(Color.blue.opacity(0.1).gradient)
        }
        .chartXAxis {
            AxisMarks(preset: .aligned) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(preset: .aligned) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondarySystemGroupedBackground)
        )
    }
}

struct AddMonitoredItemView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var monitoringState: MonitoringState
    var appState: AppState

    @State private var nodeId = ""
    @State private var displayName = ""
    @State private var selectedServer: OPCUAServer?
    @State private var isAdding = false
    @State private var errorMessage: String?

    var connectedServers: [OPCUAServer] {
        appState.servers.filter { appState.connectionManager.isConnected(to: $0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    if connectedServers.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("No connected servers")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Select Server", selection: $selectedServer) {
                            ForEach(connectedServers) { server in
                                Text(server.name).tag(server as OPCUAServer?)
                            }
                        }
                    }
                }

                Section("Item Information") {
                    TextField("Node ID (e.g., ns=2;i=2)", text: $nodeId)
                        .textFieldStyle(.roundedBorder)

                    TextField("Display Name", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }

                if let error = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Add Monitored Item")
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
                    Button("Add") {
                        addItem()
                    }
                    .disabled(nodeId.isEmpty || displayName.isEmpty || selectedServer == nil || isAdding)
                }
            }
            .onAppear {
                selectedServer = connectedServers.first
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    private func addItem() {
        guard let server = selectedServer else { return }

        isAdding = true
        errorMessage = nil

        Task {
            await monitoringState.addMonitoredItem(
                nodeId: nodeId,
                displayName: displayName,
                server: server,
                appState: appState
            )

            await MainActor.run {
                isAdding = false
                dismiss()
            }
        }
    }
}


// MARK: - Subscription Picker

struct SubscriptionPicker: View {
    let subscriptions: [Subscription]
    @Binding var selectedSubscription: Subscription?
    
    var body: some View {
        HStack {
            Text("Subscription:")
                .font(.headline)
            
            Picker("Subscription", selection: $selectedSubscription) {
                Text("All Subscriptions").tag(nil as Subscription?)
                ForEach(subscriptions) { subscription in
                    HStack {
                        Circle()
                            .fill(subscription.isActive ? .green : .gray)
                            .frame(width: 8, height: 8)
                        Text(subscription.name)
                        Text("(\(subscription.monitoredItems.count) items)")
                            .foregroundColor(.secondary)
                    }
                    .tag(subscription as Subscription?)
                }
            }
            .pickerStyle(.menu)
            
            Spacer()
            
            if let subscription = selectedSubscription {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(subscription.monitoredItems.count) items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(subscription.publishingInterval))ms interval")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(subscriptions.reduce(0) { $0 + $1.monitoredItems.count }) total items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(subscriptions.count) active subscriptions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
