import SwiftUI
import Charts
import Combine

struct ModernMonitoringDashboard: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var monitoringState = ModernMonitoringState()
    @State private var viewMode: ViewMode = .grid
    @State private var refreshInterval: Double = 1.0
    @State private var showAddItem = false
    @State private var selectedSubscription: Subscription?
    @State private var searchText = ""
    @State private var showingSettings = false

    init(selectedItemID: String? = nil) {
        let mode: ViewMode
        switch selectedItemID {
        case "trend":
            mode = .chart
        case "watchlists":
            mode = .list
        default:
            mode = .grid
        }
        _viewMode = State(initialValue: mode)
    }
    
    // Get all monitored items from all active subscriptions
    var allMonitoredItems: [MonitoredItem] {
        appState.subscriptions
            .filter { $0.isActive }
            .flatMap { $0.monitoredItems }
    }
    
    // Filter items based on selected subscription and search
    var filteredItems: [MonitoredItem] {
        var items = selectedSubscription?.monitoredItems ?? allMonitoredItems
        
        if !searchText.isEmpty {
            items = items.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText) ||
                $0.nodeId.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return items
    }
    
    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case list = "List"
        case chart = "Chart"
        case compact = "Compact"
        
        var systemImage: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            case .chart: return "chart.line.uptrend.xyaxis"
            case .compact: return "rectangle.grid.3x2"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.tertiaryBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Validation Alert
                    if !appState.lastSubscriptionValidationIssues.isEmpty {
                        ModernValidationBanner(issues: appState.lastSubscriptionValidationIssues)
                    }
                    
                    // Dashboard Content
                    if allMonitoredItems.isEmpty {
                        emptyStateView
                    } else {
                        VStack(spacing: 0) {
                            // Controls Section
                            controlsSection
                                .padding()
                                .background(DesignSystem.Colors.background)
                            
                            Divider()
                            
                            // Content View
                            ScrollView {
                                contentView
                                    .padding()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Real-Time Monitoring")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                    
                    Button(action: { showAddItem = true }) {
                        Label("Add Item", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .sheet(isPresented: $showAddItem) {
                ModernAddMonitoredItemView(monitoringState: monitoringState, appState: appState)
            }
            .sheet(isPresented: $showingSettings) {
                MonitoringSettingsView(refreshInterval: $refreshInterval)
            }
            .onAppear {
                monitoringState.setConnectionManager(appState.connectionManager)
                monitoringState.startMonitoring(interval: refreshInterval)
                appState.validateCurrentSubscriptions()
            }
            .onDisappear {
                monitoringState.stopMonitoring()
            }
            .onChange(of: refreshInterval) { _, newValue in
                monitoringState.startMonitoring(interval: newValue)
            }
        }
    }
    
    // MARK: - Controls Section
    
    var controlsSection: some View {
        VStack(spacing: DesignSystem.Spacing.small) {
            // Statistics Row
            HStack(spacing: DesignSystem.Spacing.medium) {
                StatBadge(
                    value: "\(filteredItems.count)",
                    label: "Items",
                    color: DesignSystem.Colors.primary
                )
                
                StatBadge(
                    value: "\(Int(refreshInterval * 1000))ms",
                    label: "Refresh",
                    color: DesignSystem.Colors.info
                )
                
                StatBadge(
                    value: "\(appState.subscriptions.filter { $0.isActive }.count)",
                    label: "Active Subs",
                    color: DesignSystem.Colors.success
                )
                
                Spacer()
            }
            
            // Filter Controls
            HStack(spacing: DesignSystem.Spacing.small) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DesignSystem.Colors.tertiaryText)
                        .font(.system(size: 14))
                    
                    TextField("Search items...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(DesignSystem.Spacing.xSmall)
                .background(DesignSystem.Colors.tertiaryBackground)
                .cornerRadius(DesignSystem.CornerRadius.small)
                
                // Subscription Filter
                Menu {
                    Button("All Subscriptions") {
                        selectedSubscription = nil
                    }
                    
                    Divider()
                    
                    ForEach(appState.subscriptions.filter { $0.isActive }) { subscription in
                        Button(subscription.name) {
                            selectedSubscription = subscription
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedSubscription?.name ?? "All Subscriptions")
                            .font(DesignSystem.Typography.callout)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, DesignSystem.Spacing.small)
                    .padding(.vertical, DesignSystem.Spacing.xSmall)
                    .background(DesignSystem.Colors.tertiaryBackground)
                    .cornerRadius(DesignSystem.CornerRadius.small)
                }
                
                Spacer()
                
                // View Mode Picker
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    var contentView: some View {
        switch viewMode {
        case .grid:
            gridView
        case .list:
            listView
        case .chart:
            chartView
        case .compact:
            compactView
        }
    }
    
    // MARK: - Grid View
    
    var gridView: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 280, maximum: 350), spacing: DesignSystem.Spacing.medium)
        ], spacing: DesignSystem.Spacing.medium) {
            ForEach(filteredItems) { item in
                ModernMonitoringCard(
                    item: item,
                    dataHistory: monitoringState.dataHistory[item.nodeId] ?? []
                )
            }
        }
    }
    
    // MARK: - List View
    
    var listView: some View {
        VStack(spacing: DesignSystem.Spacing.xSmall) {
            // Header
            HStack(spacing: DesignSystem.Spacing.medium) {
                Text("NAME")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("VALUE")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.tertiaryText)
                    .frame(width: 150, alignment: .leading)
                
                Text("QUALITY")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.tertiaryText)
                    .frame(width: 100, alignment: .leading)
                
                Text("UPDATED")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.tertiaryText)
                    .frame(width: 120, alignment: .trailing)
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            
            Divider()
            
            ForEach(filteredItems) { item in
                MonitoringListRow(item: item)
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.background)
        .cornerRadius(DesignSystem.CornerRadius.medium)
    }
    
    // MARK: - Chart View
    
    var chartView: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            if filteredItems.isEmpty {
                DesignSystemEmptyStateView(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "No Data",
                    message: "Select items to view their charts"
                )
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 400), spacing: DesignSystem.Spacing.medium)
                ], spacing: DesignSystem.Spacing.medium) {
                    ForEach(filteredItems.prefix(6)) { item in
                        MonitoringChartCard(item: item, dataHistory: monitoringState.dataHistory[item.nodeId] ?? [])
                    }
                }
            }
        }
    }
    
    // MARK: - Compact View
    
    var compactView: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 180, maximum: 220), spacing: DesignSystem.Spacing.small)
        ], spacing: DesignSystem.Spacing.small) {
            ForEach(filteredItems) { item in
                CompactMonitoringCard(item: item)
            }
        }
    }
    
    // MARK: - Empty State
    
    var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Spacer()
            
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 72))
                .foregroundColor(DesignSystem.Colors.tertiaryText)
                .symbolEffect(.pulse)
            
            VStack(spacing: DesignSystem.Spacing.xSmall) {
                Text("No Monitored Items")
                    .font(DesignSystem.Typography.title2)
                    .fontWeight(.semibold)
                
                Text("Add items from the address space to monitor their values in real-time")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            Button(action: { showAddItem = true }) {
                Label("Add Monitored Item", systemImage: "plus.circle.fill")
                    .font(DesignSystem.Typography.callout.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Monitoring Card

struct ModernMonitoringCard: View {
    @EnvironmentObject var appState: AppState
    let item: MonitoredItem
    let dataHistory: [DataPoint]
    
    @State private var isHovered = false
    @State private var showingDeleteConfirmation = false
    @State private var isRefreshing = false
    @State private var showingWriteSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                    Text(item.displayName)
                        .font(DesignSystem.Typography.callout.weight(.medium))
                        .lineLimit(1)
                    
                    Text(item.nodeId)
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(DesignSystem.Colors.tertiaryText)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Quality Indicator
                MonitoringQualityBadge(quality: item.quality)
            }
            .padding(DesignSystem.Spacing.medium)
            
            Divider()
            
            // Value Display
            VStack(spacing: DesignSystem.Spacing.small) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.currentValue ?? "—")
                        .font(DesignSystem.Typography.title)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    
                    Spacer()
                    
                    if let timestamp = item.timestamp {
                        Text(timestamp, style: .relative)
                            .font(DesignSystem.Typography.caption2)
                            .foregroundColor(DesignSystem.Colors.tertiaryText)
                    }
                }
                
                // Mini sparkline (real data)
                if !dataHistory.isEmpty {
                    MiniSparkline(data: dataHistory.suffix(20).map { $0.value })
                        .frame(height: 40)
                        .transition(.opacity)
                }
            }
            .padding(DesignSystem.Spacing.medium)
            .background(DesignSystem.Colors.tertiaryBackground.opacity(0.5))
            
            // Footer/Actions
            HStack {
                Label("\(Int(item.samplingInterval))ms", systemImage: "timer")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                
                Spacer()
                
                HStack(spacing: DesignSystem.Spacing.small) {
                    Button(action: { readValue() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DesignSystem.Colors.primary)
                    .disabled(isRefreshing)
                    
                    Button(action: { showingWriteSheet = true }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DesignSystem.Colors.info)
                    
                    Button(action: { showingDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DesignSystem.Colors.error)
                }
            }
            .padding(DesignSystem.Spacing.small)
            .padding(.horizontal, DesignSystem.Spacing.xSmall)
        }
        .background(DesignSystem.Colors.background)
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .shadow(color: isHovered ? .black.opacity(0.1) : .black.opacity(0.05), radius: isHovered ? 10 : 5)
        .scaleEffect(isHovered ? 1.02 : 1)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button { readValue() } label: {
                Label("Read Current Value", systemImage: "arrow.clockwise")
            }
            
            Button { showingWriteSheet = true } label: {
                Label("Write Value...", systemImage: "pencil")
            }
            
            Divider()
            
            Button { addToAnalytics() } label: {
                Label("Add to Analytics", systemImage: "chart.xyaxis.line")
            }
            
            Divider()
            
            Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                Label("Remove from Monitoring", systemImage: "trash")
            }
        }
        .confirmationDialog("Remove Item", isPresented: $showingDeleteConfirmation) {
            Button("Remove \(item.displayName)", role: .destructive) { removeItem() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to stop monitoring this item?")
        }
        .sheet(isPresented: $showingWriteSheet) {
            if let server = appState.servers.first(where: { server in
                appState.subscriptions.contains { sub in
                    sub.serverId == server.id && sub.monitoredItems.contains { it in it.id == item.id }
                }
            }) {
                ModernWriteValueView(server: server, nodeId: item.nodeId, displayName: item.displayName)
            }
        }
        .animation(DesignSystem.Animation.fast, value: isHovered)
    }
    
    private func readValue() {
        guard !isRefreshing else { return }
        
        Task {
            isRefreshing = true
            // Find server for this item
            if let server = appState.servers.first(where: { server in
                appState.subscriptions.contains { sub in
                    sub.serverId == server.id && sub.monitoredItems.contains { $0.id == item.id }
                }
            }) {
                if let newValue = await appState.connectionManager.readValue(for: server, nodeId: item.nodeId) {
                    await MainActor.run {
                        appState.updateMonitoredItemValue(nodeId: item.nodeId, value: newValue, quality: .good)
                    }
                }
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000)
            isRefreshing = false
        }
    }
    
    private func removeItem() {
        // Find the subscription containing this item
        if let subscription = appState.subscriptions.first(where: { 
            $0.monitoredItems.contains(where: { $0.id == item.id }) 
        }) {
            // Remove from server
            if let server = appState.servers.first(where: { $0.id == subscription.serverId }) {
                Task {
                    _ = await appState.connectionManager.removeMonitoredItem(for: server, nodeId: item.nodeId)
                }
            }
            
            // Remove from app state
            appState.removeMonitoredItem(item, from: subscription.id)
        }
    }
    
    private func addToAnalytics() {
        if let server = appState.servers.first(where: { server in
            appState.subscriptions.contains { sub in
                sub.serverId == server.id && sub.monitoredItems.contains { it in it.id == item.id }
            }
        }) {
            AnalyticsManager.shared.addMonitoredItem(
                nodeId: item.nodeId,
                displayName: item.displayName,
                server: server,
                unit: ""
            )
        }
    }
}

// MARK: - List Row

struct MonitoringListRow: View {
    @EnvironmentObject var appState: AppState
    let item: MonitoredItem
    @State private var isHovered = false
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            // Name and Node ID
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                Text(item.displayName)
                    .font(DesignSystem.Typography.callout)
                    .lineLimit(1)
                
                Text(item.nodeId)
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.tertiaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Value
            Text(item.currentValue ?? "—")
                .font(DesignSystem.Typography.monospacedBody)
                .frame(width: 150, alignment: .leading)
                .contentTransition(.numericText())
            
            // Quality
            MonitoringQualityBadge(quality: item.quality)
                .frame(width: 100, alignment: .leading)
            
            // Last Update
            Group {
                if let timestamp = item.timestamp {
                    Text(timestamp, style: .relative)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                } else {
                    Text("Never")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.tertiaryText)
                }
            }
            .frame(width: 120, alignment: .trailing)
            
            // Action Menu
            Menu {
                Button { readValue() } label: {
                    Label("Read", systemImage: "arrow.clockwise")
                }
                
                Button { addToAnalytics() } label: {
                    Label("Analytics", systemImage: "chart.xyaxis.line")
                }
                
                Divider()
                
                Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(DesignSystem.Spacing.medium)
        .background(isHovered ? DesignSystem.Colors.tertiaryBackground : Color.clear)
        .cornerRadius(DesignSystem.CornerRadius.small)
        .onHover { isHovered = $0 }
        .confirmationDialog("Remove Item", isPresented: $showingDeleteConfirmation) {
            Button("Remove \(item.displayName)", role: .destructive) { removeItem() }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    private func readValue() {
        Task {
            if let server = appState.servers.first(where: { server in
                appState.subscriptions.contains { sub in
                    sub.serverId == server.id && sub.monitoredItems.contains { it in it.id == item.id }
                }
            }) {
                if let newValue = await appState.connectionManager.readValue(for: server, nodeId: item.nodeId) {
                    await MainActor.run {
                        appState.updateMonitoredItemValue(nodeId: item.nodeId, value: newValue, quality: .good)
                    }
                }
            }
        }
    }
    
    private func removeItem() {
        if let subscription = appState.subscriptions.first(where: { 
            $0.monitoredItems.contains(where: { $0.id == item.id }) 
        }) {
            if let server = appState.servers.first(where: { $0.id == subscription.serverId }) {
                Task {
                    _ = await appState.connectionManager.removeMonitoredItem(for: server, nodeId: item.nodeId)
                }
            }
            appState.removeMonitoredItem(item, from: subscription.id)
        }
    }
    
    private func addToAnalytics() {
        if let server = appState.servers.first(where: { server in
            appState.subscriptions.contains { sub in
                sub.serverId == server.id && sub.monitoredItems.contains { it in it.id == item.id }
            }
        }) {
            AnalyticsManager.shared.addMonitoredItem(
                nodeId: item.nodeId,
                displayName: item.displayName,
                server: server,
                unit: ""
            )
        }
    }
}

// MARK: - Compact Card

struct CompactMonitoringCard: View {
    let item: MonitoredItem
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
            HStack {
                Text(item.displayName)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Spacer()
                
                Circle()
                    .fill(item.quality.color)
                    .frame(width: 6, height: 6)
            }
            
            Text(item.currentValue ?? "—")
                .font(DesignSystem.Typography.headline)
                .lineLimit(1)
            
            if let timestamp = item.timestamp {
                Text(timestamp, style: .relative)
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.tertiaryText)
            }
        }
        .padding(DesignSystem.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.background)
        .cornerRadius(DesignSystem.CornerRadius.small)
        .shadow(color: isHovered ? .black.opacity(0.08) : .black.opacity(0.03), radius: isHovered ? 6 : 3)
        .scaleEffect(isHovered ? 1.05 : 1)
        .onHover { isHovered = $0 }
        .animation(DesignSystem.Animation.fast, value: isHovered)
    }
}

// MARK: - Chart Card

struct MonitoringChartCard: View {
    let item: MonitoredItem
    let dataHistory: [DataPoint]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                    Text(item.displayName)
                        .font(DesignSystem.Typography.callout.weight(.medium))
                    
                    Text(item.currentValue ?? "—")
                        .font(DesignSystem.Typography.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                MonitoringQualityBadge(quality: item.quality)
            }
            
            // Chart
            if !dataHistory.isEmpty {
                Chart(dataHistory.suffix(50)) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(DesignSystem.Colors.primary)
                    
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [DesignSystem.Colors.primary.opacity(0.3), DesignSystem.Colors.primary.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .frame(height: 150)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(DesignSystem.Colors.tertiaryBackground)
                    .frame(height: 150)
                    .overlay(
                        Text("No data")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.tertiaryText)
                    )
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.background)
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .shadow(radius: 4)
    }
}

// MARK: - Supporting Components

struct MonitoringQualityBadge: View {
    let quality: NodeInfo.Quality
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xxSmall) {
            Circle()
                .fill(quality.color)
                .frame(width: 8, height: 8)
            
            Text(quality.rawValue)
                .font(DesignSystem.Typography.caption2)
                .foregroundColor(quality.color)
        }
        .padding(.horizontal, DesignSystem.Spacing.xSmall)
        .padding(.vertical, 2)
        .background(quality.color.opacity(0.1))
        .cornerRadius(DesignSystem.CornerRadius.small)
    }
}

struct StatBadge: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xSmall) {
            Text(value)
                .font(DesignSystem.Typography.callout.weight(.semibold))
                .foregroundColor(color)
            
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
        }
        .padding(.horizontal, DesignSystem.Spacing.small)
        .padding(.vertical, DesignSystem.Spacing.xxSmall)
        .background(color.opacity(0.1))
        .cornerRadius(DesignSystem.CornerRadius.small)
    }
}

struct MiniSparkline: View {
    let data: [Double]
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard !data.isEmpty else { return }
                
                let step = geometry.size.width / CGFloat(data.count - 1)
                let minValue = data.min() ?? 0
                let maxValue = data.max() ?? 1
                let range = maxValue - minValue
                
                for (index, value) in data.enumerated() {
                    let x = CGFloat(index) * step
                    let normalizedValue = range > 0 ? (value - minValue) / range : 0.5
                    let y = geometry.size.height * (1 - normalizedValue)
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(DesignSystem.Colors.primary, lineWidth: 2)
        }
    }
}

struct ModernValidationBanner: View {
    let issues: [MonitoredItemValidation]
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(DesignSystem.Colors.warning)
                
                Text("\(issues.count) validation issue\(issues.count == 1 ? "" : "s")")
                    .font(DesignSystem.Typography.callout.weight(.medium))
                
                Spacer()
                
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }
            
            if isExpanded {
                let displayIssues = Array(issues.prefix(3))
                ForEach(displayIssues, id: \.nodeId) { issue in
                    if let description = issue.issue?.description {
                        Text("• \(description)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.small)
        .background(DesignSystem.Colors.warning.opacity(0.1))
        .overlay(
            Rectangle()
                .fill(DesignSystem.Colors.warning)
                .frame(width: 3),
            alignment: .leading
        )
        .animation(DesignSystem.Animation.fast, value: isExpanded)
    }
}

struct MonitoringSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var refreshInterval: Double
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Refresh Settings") {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                        Text("Refresh Interval: \(Int(refreshInterval * 1000))ms")
                            .font(DesignSystem.Typography.callout)
                        
                        Slider(value: $refreshInterval, in: 0.1...5.0, step: 0.1)
                        
                        HStack(spacing: DesignSystem.Spacing.small) {
                            ForEach([0.1, 0.5, 1.0, 2.0, 5.0], id: \.self) { interval in
                                Button("\(Int(interval * 1000))ms") {
                                    refreshInterval = interval
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Monitoring Settings")
            // .navigationBarTitleDisplayMode(.inline) // iOS only
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 300)
        #endif
    }
}

// MARK: - Data Point Model
// DataPoint is defined in OPCUAModels.swift

// MARK: - Monitoring State

@MainActor
class ModernMonitoringState: ObservableObject {
    @Published var selectedItems: Set<MonitoredItem> = []
    @Published var dataHistory: [String: [DataPoint]] = [:]
    
    private var connectionManager: OPCUAConnectionManager?
    private var cancellables = Set<AnyCancellable>()
    
    func setConnectionManager(_ manager: OPCUAConnectionManager) {
        self.connectionManager = manager
        setupNotifications()
    }
    
    private func setupNotifications() {
        cancellables.removeAll()
        
        NotificationCenter.default.publisher(for: .opcuaDataChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let userInfo = notification.userInfo,
                      let nodeId = userInfo["nodeId"] as? String,
                      let value = userInfo["value"] as? String else {
                    return
                }
                
                self.updateHistory(nodeId: nodeId, value: value)
            }
            .store(in: &cancellables)
    }
    
    func startMonitoring(interval: Double) {
        // Monitoring is handled by subscriptions in OPCUAConnectionManager
        // This method can be used for UI-specific polling if needed, 
        // but for now, we rely on the live subscription updates.
    }
    
    func stopMonitoring() {
        // Nothing to stop as we use notifications
    }
    
    private func updateHistory(nodeId: String, value: String) {
        let now = Date()
        
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

#Preview {
    ModernMonitoringDashboard()
        .environmentObject(AppState())
}
