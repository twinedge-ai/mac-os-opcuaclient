import SwiftUI
import Charts
import UniformTypeIdentifiers

struct ModernAnalyticsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var analytics = AnalyticsManager.shared
    @State private var selectedTimeRange: TimeRange = .fiveMinutes
    @State private var showingAddItem = false
    @State private var showingExport = false
    @State private var chartMode: ChartMode = .multiLine
    @State private var selectedItemForDetail: TrackedItem?
    @State private var viewMode: ViewMode = .dashboard
    @State private var showingSettings = false
    @State private var searchText = ""

    init(selectedItemID: String? = nil) {
        let mode: ViewMode
        switch selectedItemID {
        case "comparison":
            mode = .comparison
        case "trends":
            mode = .detailed
        default:
            mode = .dashboard
        }
        _viewMode = State(initialValue: mode)
        _showingExport = State(initialValue: selectedItemID == "export")
    }
    
    enum ViewMode: String, CaseIterable {
        case dashboard = "Dashboard"
        case detailed = "Trends"
        case comparison = "Comparison"
        
        var icon: String {
            switch self {
            case .dashboard: return "rectangle.grid.3x2"
            case .detailed: return "chart.line.uptrend.xyaxis"
            case .comparison: return "chart.bar.xaxis"
            }
        }
    }
    
    enum TimeRange: String, CaseIterable {
        case oneMinute = "1 Min"
        case fiveMinutes = "5 Min"
        case fifteenMinutes = "15 Min"
        case oneHour = "1 Hour"
        case sixHours = "6 Hours"
        case oneDay = "1 Day"
        
        var seconds: TimeInterval {
            switch self {
            case .oneMinute: return 60
            case .fiveMinutes: return 300
            case .fifteenMinutes: return 900
            case .oneHour: return 3600
            case .sixHours: return 21600
            case .oneDay: return 86400
            }
        }
        
        var shortLabel: String {
            switch self {
            case .oneMinute: return "1m"
            case .fiveMinutes: return "5m"
            case .fifteenMinutes: return "15m"
            case .oneHour: return "1h"
            case .sixHours: return "6h"
            case .oneDay: return "1d"
            }
        }
    }
    
    enum ChartMode: String, CaseIterable {
        case multiLine = "Lines"
        case stacked = "Stacked"
        case comparison = "Compare"
        case heatmap = "Heatmap"
        
        var icon: String {
            switch self {
            case .multiLine: return "chart.xyaxis.line"
            case .stacked: return "chart.bar.fill"
            case .comparison: return "chart.pie.fill"
            case .heatmap: return "grid.circle.fill"
            }
        }
    }
    
    var hasConnectedServers: Bool {
        appState.servers.contains { server in
            appState.connectionManager.getConnectionStatus(for: server) == .connected
        }
    }
    
    var filteredItems: [TrackedItem] {
        if searchText.isEmpty {
            return analytics.monitoredItems
        }
        return analytics.monitoredItems.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.nodeId.localizedCaseInsensitiveContains(searchText)
        }
    }

    var selectedChartItems: [TrackedItem] {
        filteredItems.filter { analytics.selectedItemsForChart.contains($0.nodeId) }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.tertiaryBackground
                    .ignoresSafeArea()
                
                if !hasConnectedServers {
                    noConnectionView
                } else if analytics.monitoredItems.isEmpty {
                    noItemsView
                } else {
                    mainContentView
                }
            }
            .navigationTitle("Analytics")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                    
                    Button(action: { showingExport = true }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    
                    Button(action: { showingAddItem = true }) {
                        Label("Add Item", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .sheet(isPresented: $showingAddItem) {
                ModernAddTrackedItemView()
            }
            .sheet(isPresented: $showingExport) {
                AnalyticsExportView(analytics: analytics)
            }
            .sheet(isPresented: $showingSettings) {
                AnalyticsSettingsView(
                    timeRange: $selectedTimeRange,
                    chartMode: $chartMode,
                    viewMode: $viewMode
                )
            }
        }
        .onAppear {
            analytics.connectionManager = appState.connectionManager
        }
    }
    
    // MARK: - Main Content
    
    var mainContentView: some View {
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
    
    var controlsSection: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            // Top row - Stats
            HStack(spacing: DesignSystem.Spacing.medium) {
                StatCard(
                    title: "Items",
                    value: Double(analytics.monitoredItems.count),
                    unit: "",
                    trend: .neutral,
                    color: DesignSystem.Colors.primary
                )
                
                StatCard(
                    title: "Active",
                    value: Double(analytics.monitoredItems.filter { $0.isActive }.count),
                    unit: "",
                    trend: .neutral,
                    color: DesignSystem.Colors.success
                )
                
                StatCard(
                    title: "Data Points",
                    value: Double(analytics.itemDataHistory.values.reduce(0) { $0 + $1.count }),
                    unit: "",
                    trend: .neutral,
                    color: DesignSystem.Colors.info
                )
                
                StatCard(
                    title: "Avg Update",
                    value: 100.0,
                    unit: "ms",
                    trend: .neutral,
                    color: DesignSystem.Colors.warning
                )
            }
            
            // Controls row
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
                
                Spacer()
                
                // Time Range
                Menu {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Button(range.rawValue) {
                            selectedTimeRange = range
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "clock")
                        Text(selectedTimeRange.shortLabel)
                    }
                    .font(DesignSystem.Typography.caption)
                    .padding(.horizontal, DesignSystem.Spacing.small)
                    .padding(.vertical, DesignSystem.Spacing.xSmall)
                    .background(DesignSystem.Colors.primary.opacity(0.1))
                    .cornerRadius(DesignSystem.CornerRadius.small)
                }
                
                // Chart Mode
                Menu {
                    ForEach(ChartMode.allCases, id: \.self) { mode in
                        Button(action: { chartMode = mode }) {
                            Label(mode.rawValue, systemImage: mode.icon)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: chartMode.icon)
                        Text(chartMode.rawValue)
                    }
                    .font(DesignSystem.Typography.caption)
                    .padding(.horizontal, DesignSystem.Spacing.small)
                    .padding(.vertical, DesignSystem.Spacing.xSmall)
                    .background(DesignSystem.Colors.info.opacity(0.1))
                    .cornerRadius(DesignSystem.CornerRadius.small)
                }

                // Node Selection
                Menu {
                    Button("Select All") {
                        analytics.selectedItemsForChart = Set(filteredItems.map(\.nodeId))
                    }
                    Button("Clear Selection") {
                        analytics.selectedItemsForChart.removeAll()
                    }
                    Divider()
                    ForEach(filteredItems) { item in
                        Button {
                            analytics.toggleItemSelection(nodeId: item.nodeId)
                        } label: {
                            Label(
                                item.displayName,
                                systemImage: analytics.selectedItemsForChart.contains(item.nodeId) ? "checkmark.circle.fill" : "circle"
                            )
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "checklist")
                        Text("\(selectedChartItems.count) Nodes")
                    }
                    .font(DesignSystem.Typography.caption)
                    .padding(.horizontal, DesignSystem.Spacing.small)
                    .padding(.vertical, DesignSystem.Spacing.xSmall)
                    .background(DesignSystem.Colors.success.opacity(0.1))
                    .cornerRadius(DesignSystem.CornerRadius.small)
                }
                
                // View Mode
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
        }
    }
    
    @ViewBuilder
    var contentView: some View {
        switch viewMode {
        case .dashboard:
            dashboardView
        case .detailed:
            detailedView
        case .comparison:
            comparisonView
        }
    }
    
    // MARK: - Dashboard View
    
    var dashboardView: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            // Main Chart
            ModernCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    HStack {
                        SectionHeader("OVERVIEW", icon: chartMode.icon)
                        Spacer()
                        Text(selectedTimeRange.rawValue)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                    
                    modernChart
                        .frame(height: 300)
                }
            }
            
            // Item Grid
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 280, maximum: 350), spacing: DesignSystem.Spacing.medium)
            ], spacing: DesignSystem.Spacing.medium) {
                ForEach(filteredItems.prefix(8)) { item in
                    AnalyticsItemCard(
                        item: item,
                        analytics: analytics,
                        isSelected: analytics.selectedItemsForChart.contains(item.nodeId),
                        onSelect: {
                            selectedItemForDetail = item
                            analytics.toggleItemSelection(nodeId: item.nodeId)
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Detailed View
    
    var detailedView: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            if let selectedItem = selectedItemForDetail ?? selectedChartItems.first {
                DetailedItemView(item: selectedItem, analytics: analytics, timeRange: selectedTimeRange)
            } else {
                itemSelectionPrompt
            }
        }
    }
    
    // MARK: - Comparison View
    
    var comparisonView: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            ModernCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    SectionHeader("ITEM COMPARISON", icon: "chart.bar.xaxis")
                    
                    ComparisonChart(items: selectedChartItems, analytics: analytics, timeRange: selectedTimeRange)
                        .frame(height: 400)
                }
            }
            
            HStack(spacing: DesignSystem.Spacing.medium) {
                ModernCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        SectionHeader("STATISTICS", icon: "number.circle")
                        
                        VStack(spacing: DesignSystem.Spacing.small) {
                            ForEach(selectedChartItems.prefix(5)) { item in
                                HStack {
                                    Circle()
                                        .fill(itemColor(for: item))
                                        .frame(width: 8, height: 8)
                                    
                                    Text(item.displayName)
                                        .font(DesignSystem.Typography.caption)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    Text("\(analytics.getLatestValue(for: item) ?? "—")")
                                        .font(DesignSystem.Typography.monospacedCaption)
                                }
                            }
                        }
                    }
                }
                
                ModernCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        SectionHeader("TRENDS", icon: "arrow.up.right")
                        
                        VStack(spacing: DesignSystem.Spacing.small) {
                            ForEach(selectedChartItems.prefix(5)) { item in
                                HStack {
                                    Text(item.displayName)
                                        .font(DesignSystem.Typography.caption)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    TrendIndicator(trend: analytics.getTrend(for: item))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Charts
    
    var modernChart: some View {
        Chart {
            ForEach(selectedChartItems.prefix(6)) { item in
                ForEach(filteredHistory(for: item), id: \.timestamp) { point in
                    chartMark(for: point, item: item)
                }
                .foregroundStyle(itemColor(for: item))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 1)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartLegend(position: .bottom, spacing: 8)
    }

    @ChartContentBuilder
    private func chartMark(for point: DataPoint, item: TrackedItem) -> some ChartContent {
        switch chartMode {
        case .multiLine:
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Value", point.value)
            )
        case .stacked:
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Value", point.value)
            )
        case .comparison:
            BarMark(
                x: .value("Time", point.timestamp),
                y: .value("Value", point.value)
            )
        case .heatmap:
            RectangleMark(
                x: .value("Time", point.timestamp),
                y: .value("Item", item.displayName)
            )
        }
    }
    
    // MARK: - Empty States
    
    var noConnectionView: some View {
        DesignSystemEmptyStateView(
            icon: "wifi.slash",
            title: "No Connected Servers",
            message: "Connect to a server to start collecting analytics data",
            action: {
                appState.selectedTab = .servers
            },
            actionLabel: "Go to Servers"
        )
    }
    
    var noItemsView: some View {
        DesignSystemEmptyStateView(
            icon: "chart.xyaxis.line",
            title: "No Tracked Items",
            message: "Add monitored items to start collecting analytics data and viewing trends",
            action: {
                showingAddItem = true
            },
            actionLabel: "Add Item"
        )
    }
    
    var itemSelectionPrompt: some View {
        DesignSystemEmptyStateView(
            icon: "chart.line.uptrend.xyaxis",
            title: "Select an Item",
            message: "Choose an item to view detailed analytics and historical data"
        )
    }
    
    // MARK: - Helper Methods
    
    private func itemColor(for item: TrackedItem) -> Color {
        let colors: [Color] = [
            .blue, .green, .orange, .purple, .red, .pink, .yellow, .cyan
        ]
        // Use a stable hash of the nodeId for consistent colors
        let hashValue = abs(item.nodeId.hashValue)
        return colors[hashValue % colors.count]
    }
    
    private func normalizedValue(_ value: Double) -> Double {
        // Normalize value between 0 and 1 for heatmap opacity
        return min(max(value / 100.0, 0.1), 1.0)
    }

    private func filteredHistory(for item: TrackedItem) -> [DataPoint] {
        let cutoff = Date().addingTimeInterval(-selectedTimeRange.seconds)
        return (analytics.itemDataHistory[item.nodeId] ?? []).filter { $0.timestamp >= cutoff }
    }
}

// MARK: - Analytics Item Card

struct AnalyticsItemCard: View {
    let item: TrackedItem
    let analytics: AnalyticsManager
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    private var latestValue: String {
        String(format: "%.2f", item.currentValue)
    }
    
    private var trend: Trend {
        analytics.getTrend(for: item)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
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
                
                Circle()
                    .fill(item.isActive ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
                    .frame(width: 8, height: 8)
            }
            
            // Value Display
            HStack(alignment: .firstTextBaseline) {
                Text(latestValue)
                    .font(DesignSystem.Typography.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                TrendIndicator(trend: trend)
            }
            
            // Mini Chart
            MiniAnalyticsChart(
                dataPoints: analytics.itemDataHistory[item.nodeId] ?? [],
                color: .accentColor
            )
            .frame(height: 40)
            
            // Footer Stats
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Updates")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(DesignSystem.Colors.tertiaryText)
                    
                    Text("\(analytics.getUpdateCount(for: item))")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Avg Rate")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(DesignSystem.Colors.tertiaryText)
                    
                    Text("\(Int(analytics.updateInterval * 1000))ms")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.background)
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .shadow(color: isHovered ? .black.opacity(0.1) : .black.opacity(0.05), radius: isHovered ? 8 : 4)
        .scaleEffect(isSelected ? 1.02 : isHovered ? 1.01 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .stroke(isSelected ? DesignSystem.Colors.primary : Color.clear, lineWidth: 2)
        )
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
        .animation(DesignSystem.Animation.fast, value: isHovered)
        .animation(DesignSystem.Animation.fast, value: isSelected)
    }
}

// MARK: - Detailed Item View

struct DetailedItemView: View {
    let item: TrackedItem
    let analytics: AnalyticsManager
    let timeRange: ModernAnalyticsView.TimeRange
    
    var dataPoints: [DataPoint] {
        let cutoff = Date().addingTimeInterval(-timeRange.seconds)
        return (analytics.itemDataHistory[item.nodeId] ?? []).filter { $0.timestamp >= cutoff }
    }
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            // Header Card
            ModernCard {
                HStack {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                        Text(item.displayName)
                            .font(DesignSystem.Typography.title2)
                            .fontWeight(.semibold)
                        
                        Text(item.nodeId)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: DesignSystem.Spacing.small) {
                        Text(String(format: "%.2f", item.currentValue))
                            .font(DesignSystem.Typography.largeTitle)
                            .fontWeight(.bold)
                        
                        TrendIndicator(trend: analytics.getTrend(for: item))
                    }
                }
            }
            
            // Detailed Chart
            ModernCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    SectionHeader("VALUE HISTORY", icon: "chart.xyaxis.line")
                    
                    Chart(dataPoints, id: \.timestamp) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(.blue)
                        .symbol(Circle().strokeBorder(lineWidth: 1))
                        
                        AreaMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .frame(height: 250)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .minute, count: 5)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour().minute())
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine()
                            AxisValueLabel()
                        }
                    }
                }
            }
            
            // Statistics Cards
            HStack(spacing: DesignSystem.Spacing.medium) {
                StatisticCard(
                    title: "MIN",
                    value: String(format: "%.2f", analytics.getMinValue(for: item)),
                    color: DesignSystem.Colors.error
                )
                
                StatisticCard(
                    title: "MAX",
                    value: String(format: "%.2f", analytics.getMaxValue(for: item)),
                    color: DesignSystem.Colors.success
                )
                
                StatisticCard(
                    title: "AVG",
                    value: String(format: "%.2f", analytics.getAverageValue(for: item)),
                    color: DesignSystem.Colors.info
                )
                
                StatisticCard(
                    title: "LAST",
                    value: analytics.getLatestValue(for: item) ?? "—",
                    color: DesignSystem.Colors.primary
                )
            }
        }
    }
}

// MARK: - Supporting Components


struct MiniAnalyticsChart: View {
    let dataPoints: [DataPoint]
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            if !dataPoints.isEmpty {
                Path { path in
                    let stepX = geometry.size.width / CGFloat(max(dataPoints.count - 1, 1))
                    let minY = dataPoints.map(\.value).min() ?? 0
                    let maxY = dataPoints.map(\.value).max() ?? 1
                    let rangeY = maxY - minY
                    
                    for (index, point) in dataPoints.enumerated() {
                        let x = CGFloat(index) * stepX
                        let normalizedY = rangeY > 0 ? (point.value - minY) / rangeY : 0.5
                        let y = geometry.size.height * (1 - normalizedY)
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, lineWidth: 2)
            }
        }
    }
}

struct StatisticCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xSmall) {
            Text(title)
                .font(DesignSystem.Typography.caption2)
                .foregroundColor(DesignSystem.Colors.tertiaryText)
            
            Text(value)
                .font(DesignSystem.Typography.title3)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.background)
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

struct ComparisonChart: View {
    let items: [TrackedItem]
    let analytics: AnalyticsManager
    let timeRange: ModernAnalyticsView.TimeRange

    private func filteredHistory(for item: TrackedItem) -> [DataPoint] {
        let cutoff = Date().addingTimeInterval(-timeRange.seconds)
        return (analytics.itemDataHistory[item.nodeId] ?? []).filter { $0.timestamp >= cutoff }
    }
    
    var body: some View {
        Chart {
            ForEach(items.prefix(5)) { item in
                ForEach(filteredHistory(for: item), id: \.timestamp) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(by: .value("Item", item.displayName))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartLegend(position: .bottom)
    }
}

// MARK: - Settings and Export Views

struct AnalyticsSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var timeRange: ModernAnalyticsView.TimeRange
    @Binding var chartMode: ModernAnalyticsView.ChartMode
    @Binding var viewMode: ModernAnalyticsView.ViewMode
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Picker("View Mode", selection: $viewMode) {
                        ForEach(ModernAnalyticsView.ViewMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    
                    Picker("Chart Type", selection: $chartMode) {
                        ForEach(ModernAnalyticsView.ChartMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                }
                
                Section("Time Range") {
                    Picker("Default Range", selection: $timeRange) {
                        ForEach(ModernAnalyticsView.TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                }
            }
            .navigationTitle("Analytics Settings")
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

struct AnalyticsExportView: View {
    @Environment(\.dismiss) var dismiss
    let analytics: AnalyticsManager
    @State private var exportFormat: ExportFormat = .csv
    @State private var timeRange: ModernAnalyticsView.TimeRange = .oneHour
    @State private var selectedNodeIds = Set<String>()
    @State private var exportError: String?

    private var exportableItems: [TrackedItem] {
        analytics.monitoredItems.filter { selectedNodeIds.contains($0.nodeId) }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Export Options") {
                    Picker("Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Picker("Time Range", selection: $timeRange) {
                        ForEach(ModernAnalyticsView.TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                }
                
                Section("Items to Export") {
                    HStack {
                        Button("Select All") {
                            selectedNodeIds = Set(analytics.monitoredItems.map(\.nodeId))
                        }
                        Button("Clear") {
                            selectedNodeIds.removeAll()
                        }
                        Spacer()
                        Text("\(exportableItems.count) selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ForEach(analytics.monitoredItems) { item in
                        Toggle(isOn: .init(
                            get: { selectedNodeIds.contains(item.nodeId) },
                            set: { isSelected in
                                if isSelected {
                                    selectedNodeIds.insert(item.nodeId)
                                } else {
                                    selectedNodeIds.remove(item.nodeId)
                                }
                            }
                        )) {
                            VStack(alignment: .leading) {
                                Text(item.displayName)
                                    .font(.callout)
                                Text(item.nodeId)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Text("Export uses the same tracked analytics items and time range shown in trends and comparison.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Export Analytics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        exportData()
                    }
                    .disabled(selectedNodeIds.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
        .onAppear {
            selectedNodeIds = analytics.selectedItemsForChart.isEmpty
                ? Set(analytics.monitoredItems.map(\.nodeId))
                : analytics.selectedItemsForChart
        }
        .alert("Export Failed", isPresented: .init(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }
    
    private func exportData() {
        let savePanel = NSSavePanel()
        let fileExtension = exportFormat.fileExtension
        savePanel.allowedContentTypes = exportFormat == .csv ? [.commaSeparatedText] : [.json]
        savePanel.nameFieldStringValue = "analytics_export_\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    let since = Date().addingTimeInterval(-timeRange.seconds)
                    guard let data = analytics.exportCombinedData(
                        for: Array(selectedNodeIds),
                        format: exportFormat,
                        since: since
                    ) else {
                        exportError = "No analytics data matched the selected nodes and time range."
                        return
                    }

                    try data.write(to: url, options: .atomic)
                    dismiss()
                } catch {
                    exportError = error.localizedDescription
                }
            }
        }
    }
}

struct ModernAddTrackedItemView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @StateObject private var analytics = AnalyticsManager.shared
    @State private var selectedServer: OPCUAServer?
    @State private var nodeId = ""
    @State private var displayName = ""
    @State private var unit = ""
    @State private var showingNodePicker = false
    @State private var previewValue: String?
    @State private var isAdding = false
    @State private var errorMessage: String?

    private var connectedServers: [OPCUAServer] {
        appState.servers.filter { appState.connectionManager.getConnectionStatus(for: $0) == .connected }
    }

    private var canAdd: Bool {
        selectedServer != nil &&
        !nodeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isAdding
    }
    
    var body: some View {
        Group {
            if showingNodePicker, let selectedServer {
                OPCUANodeValuePicker(
                    server: selectedServer,
                    appState: appState,
                    title: "Select Analytics Node",
                    instruction: "Choose a Variable node that returns a numeric value for analytics, trends, comparison, and export.",
                    confirmTitle: "Use Node",
                    requiresReadableValue: true,
                    requiresNumericValue: true,
                    duplicateNodeIds: Set(analytics.monitoredItems.map(\.nodeId)),
                    onSelect: { node, value in
                        applySelectedNode(node, previewValue: value)
                    },
                    onCancel: {
                        showingNodePicker = false
                    }
                )
            } else {
                NavigationStack {
                    Form {
                        Section("Server") {
                            Picker("Connected Server", selection: $selectedServer) {
                                Text("Select a server").tag(nil as OPCUAServer?)
                                ForEach(connectedServers) { server in
                                    Text(server.name).tag(Optional(server))
                                }
                            }
                        }

                        Section("Item") {
                            Button {
                                openNodePicker()
                            } label: {
                                Label("Browse Address Space", systemImage: "folder.badge.gearshape")
                            }
                            .disabled(selectedServer == nil)

                            TextField("Node ID", text: $nodeId)
                            TextField("Display Name", text: $displayName)
                            TextField("Unit", text: $unit)

                            if let previewValue {
                                Label("Readable numeric value: \(previewValue)", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }

                        if let errorMessage {
                            Section {
                                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }

                        Section {
                            Text("Analytics reads numeric OPC UA values from the selected node every second and uses the same tracked items for dashboard charts, trends, comparison, and export.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .navigationTitle("Add Tracked Item")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button(isAdding ? "Adding..." : "Add") {
                                Task { await addItem() }
                            }
                            .disabled(!canAdd)
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: showingNodePicker ? 820 : 500, minHeight: showingNodePicker ? 620 : 420)
        #endif
        .onAppear {
            analytics.connectionManager = appState.connectionManager
            selectedServer = selectedServer ?? connectedServers.first
        }
    }

    private func openNodePicker() {
        guard let selectedServer else {
            errorMessage = "Select a connected server before browsing nodes."
            return
        }

        guard appState.connectionManager.isConnected(to: selectedServer) else {
            errorMessage = "No OPC UA server is connected for \(selectedServer.name)."
            return
        }

        errorMessage = nil
        showingNodePicker = true
    }

    private func applySelectedNode(_ node: NodeInfo, previewValue: String?) {
        nodeId = node.nodeId
        displayName = node.displayName
        self.previewValue = previewValue
        errorMessage = nil
        showingNodePicker = false
    }

    @MainActor
    private func addItem() async {
        guard let server = selectedServer else { return }

        let trimmedNodeId = nodeId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)

        isAdding = true
        errorMessage = nil

        guard analytics.monitoredItems.contains(where: { $0.nodeId == trimmedNodeId }) == false else {
            errorMessage = "This node is already tracked in analytics."
            isAdding = false
            return
        }

        guard let value = await appState.connectionManager.readValue(for: server, nodeId: trimmedNodeId),
              let numericValue = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Analytics requires a readable numeric value. Browse and select a Variable node, or verify the Node ID."
            isAdding = false
            return
        }

        analytics.addMonitoredItem(
            nodeId: trimmedNodeId,
            displayName: trimmedDisplayName,
            server: server,
            unit: trimmedUnit,
            initialValue: numericValue
        )
        dismiss()
    }
}

// Trend mapping and conversion
extension Trend {
    var dataTrendType: DataTrendType {
        switch self {
        case .increasing: return .up
        case .decreasing: return .down
        case .stable: return .neutral
        }
    }
}

// Map from real Trend to UI component TrendIndicator
struct TrendIndicator: View {
    let trend: Trend
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xxSmall) {
            Image(systemName: trend.systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(trend.color)
            
            Text(trend.rawValue)
                .font(DesignSystem.Typography.caption2)
                .foregroundColor(trend.color)
        }
    }
}

extension AnalyticsManager {
    func getTrend(for item: TrackedItem) -> Trend {
        return analysisResults[item.nodeId]?.trend ?? .stable
    }
    
    func getLatestValue(for item: TrackedItem) -> String? {
        return String(format: "%.2f", item.currentValue)
    }
    
    func getUpdateCount(for item: TrackedItem) -> Int {
        return itemDataHistory[item.nodeId]?.count ?? 0
    }
    
    func getMinValue(for item: TrackedItem) -> Double {
        if let min = analysisResults[item.nodeId]?.min {
            return min
        }
        return itemDataHistory[item.nodeId]?.map(\.value).min() ?? item.currentValue
    }
    
    func getMaxValue(for item: TrackedItem) -> Double {
        if let max = analysisResults[item.nodeId]?.max {
            return max
        }
        return itemDataHistory[item.nodeId]?.map(\.value).max() ?? item.currentValue
    }
    
    func getAverageValue(for item: TrackedItem) -> Double {
        if let mean = analysisResults[item.nodeId]?.mean {
            return mean
        }
        let values = itemDataHistory[item.nodeId]?.map(\.value) ?? []
        guard !values.isEmpty else { return item.currentValue }
        return values.reduce(0, +) / Double(values.count)
    }
}

#Preview {
    ModernAnalyticsView()
        .environmentObject(AppState())
}
