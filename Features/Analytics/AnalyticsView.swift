import SwiftUI
import UniformTypeIdentifiers
import Charts

struct AnalyticsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var analytics = AnalyticsManager.shared
    @State private var selectedTimeRange: TimeRange = .fiveMinutes
    @State private var showingAddItem = false
    @State private var showingExport = false
    @State private var chartMode: ChartMode = .multiLine
    @State private var selectedItemForDetail: TrackedItem?

    enum TimeRange: String, CaseIterable {
        case oneMinute = "1 Min"
        case fiveMinutes = "5 Min"
        case fifteenMinutes = "15 Min"
        case oneHour = "1 Hour"

        var seconds: TimeInterval {
            switch self {
            case .oneMinute: return 60
            case .fiveMinutes: return 300
            case .fifteenMinutes: return 900
            case .oneHour: return 3600
            }
        }
    }

    enum ChartMode: String, CaseIterable {
        case multiLine = "Multi-Line"
        case stacked = "Stacked"
        case comparison = "Comparison"

        var systemImage: String {
            switch self {
            case .multiLine: return "chart.xyaxis.line"
            case .stacked: return "chart.bar.fill"
            case .comparison: return "chart.pie.fill"
            }
        }
    }

    var hasConnectedServers: Bool {
        appState.servers.contains { server in
            appState.connectionManager.getConnectionStatus(for: server) == .connected
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !hasConnectedServers {
                // No connected servers - show connection prompt
                NoConnectionView()
            } else if analytics.monitoredItems.isEmpty {
                // Connected but no items - show add items prompt
                NoItemsView(showingAddItem: $showingAddItem)
            } else {
                // Normal analytics view
                AnalyticsHeader(
                    timeRange: $selectedTimeRange,
                    chartMode: $chartMode,
                    showingAddItem: $showingAddItem,
                    showingExport: $showingExport,
                    analytics: analytics
                )

                NavigationSplitView {
                    // Sidebar - Item list
                    ItemListPanel(
                        analytics: analytics,
                        selectedItem: $selectedItemForDetail,
                        appState: appState
                    )
                    .navigationTitle("Analytics Items")
                    #if os(macOS)
                    .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
                    #endif
                } detail: {
                    // Main content
                    #if os(macOS)
                    VStack(spacing: 16) {
                        // Multi-item chart
                        MultiItemChartView(
                            analytics: analytics,
                            timeRange: selectedTimeRange,
                            chartMode: chartMode
                        )
                        .frame(minHeight: 300)

                        // Analysis panels
                        HStack(spacing: 16) {
                            StatisticsPanel(analytics: analytics)
                            if let item = selectedItemForDetail {
                                ItemDetailPanel(item: item, analytics: analytics)
                            } else {
                                ComparisonPanel(analytics: analytics)
                            }
                        }
                        .frame(height: 200)
                    }
                    .padding()
                    #else
                    ScrollView {
                        VStack(spacing: 16) {
                            // Multi-item chart
                            MultiItemChartView(
                                analytics: analytics,
                                timeRange: selectedTimeRange,
                                chartMode: chartMode
                            )
                            .frame(minHeight: 300)

                            // Analysis panels
                            VStack(spacing: 16) {
                                StatisticsPanel(analytics: analytics)
                                if let item = selectedItemForDetail {
                                    ItemDetailPanel(item: item, analytics: analytics)
                                } else {
                                    ComparisonPanel(analytics: analytics)
                                }
                            }
                        }
                        .padding()
                    }
                    #endif
                }
            }
        }
        .navigationTitle("Analytics")
        .sheet(isPresented: $showingAddItem) {
            AddAnalyticsItemView(analytics: analytics, appState: appState)
        }
        .sheet(isPresented: $showingExport) {
            ExportDataView(analytics: analytics)
        }
        .onAppear {
            // Set connection manager reference
            analytics.connectionManager = appState.connectionManager
        }
    }
}

// MARK: - Empty States

struct NoConnectionView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "server.rack")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No Server Connected")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Connect to an OPC UA server to start monitoring and analyzing data.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button(action: {
                Task { @MainActor in
                    appState.selectedTab = .servers
                }
            }) {
                Label("Go to Servers", systemImage: "server.rack")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondarySystemBackground)
    }
}

struct NoItemsView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showingAddItem: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No Items to Monitor")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add variables from the Address Space Browser to start tracking and analyzing their values over time.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 450)

            HStack(spacing: 16) {
                Button(action: {
                    Task { @MainActor in
                        appState.selectedTab = .browse
                    }
                }) {
                    Label("Browse Address Space", systemImage: "folder.fill.badge.gearshape")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: { showingAddItem = true }) {
                    Label("Add Item Manually", systemImage: "plus.circle")
                        .frame(minWidth: 150)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("How to add items:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                HStack(alignment: .top, spacing: 8) {
                    Text("1.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Go to Browse tab and connect to a server")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("2.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Right-click on a variable node")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("3.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Select \"Add to Analytics Chart\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondarySystemBackground)
    }
}

// MARK: - Header

struct AnalyticsHeader: View {
    @Binding var timeRange: AnalyticsView.TimeRange
    @Binding var chartMode: AnalyticsView.ChartMode
    @Binding var showingAddItem: Bool
    @Binding var showingExport: Bool
    @ObservedObject var analytics: AnalyticsManager

    var body: some View {
        HStack {
            // Time range picker
            Picker("Time Range", selection: $timeRange) {
                ForEach(AnalyticsView.TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            Spacer()

            // Chart mode picker
            Picker("Chart Mode", selection: $chartMode) {
                ForEach(AnalyticsView.ChartMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 250)

            Spacer()

            // Actions
            Button(action: { analytics.clearAllData() }) {
                Label("Clear Data", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(analytics.monitoredItems.isEmpty)

            Button(action: { showingExport = true }) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(analytics.monitoredItems.isEmpty)

            Button(action: { showingAddItem = true }) {
                Label("Add Item", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.secondarySystemBackground)
    }
}

// MARK: - Item List Panel

struct ItemListPanel: View {
    @ObservedObject var analytics: AnalyticsManager
    @Binding var selectedItem: TrackedItem?
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Monitored Items")
                    .font(.headline)
                Spacer()
                Text("\(analytics.monitoredItems.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondarySystemBackground)

            List(selection: $selectedItem) {
                ForEach(analytics.monitoredItems) { item in
                    ItemRow(item: item, analytics: analytics, appState: appState)
                        .tag(item)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        analytics.removeMonitoredItem(nodeId: analytics.monitoredItems[index].nodeId)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

struct ItemRow: View {
    let item: TrackedItem
    @ObservedObject var analytics: AnalyticsManager
    let appState: AppState

    var isSelected: Bool {
        analytics.selectedItemsForChart.contains(item.nodeId)
    }

    var isConnected: Bool {
        appState.connectionManager.getConnectionStatus(for: item.server) == .connected && item.isConnected
    }

    var body: some View {
        HStack(spacing: 12) {
            // Color indicator & selection toggle
            Button(action: { analytics.toggleItemSelection(nodeId: item.nodeId) }) {
                Circle()
                    .fill(isSelected ? item.color : item.color.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(item.color, lineWidth: 2)
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.displayName)
                        .font(.caption)
                        .fontWeight(.medium)

                    if !item.isActive {
                        Text("PAUSED")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }

                    if !isConnected {
                        Text("OFFLINE")
                            .font(.caption2)
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                            .background(Color.red.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                Text(item.server.name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isConnected {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f", item.currentValue))
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)

                    if !item.unit.isEmpty {
                        Text(item.unit)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Trend indicator
                if let analysis = analytics.getAnalysis(for: item.nodeId) {
                    Image(systemName: analysis.trend.systemImage)
                        .font(.caption)
                        .foregroundColor(analysis.trend.color)
                }
            } else {
                Text("--")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(action: { analytics.toggleItemActive(nodeId: item.nodeId) }) {
                Label(item.isActive ? "Pause" : "Resume", systemImage: item.isActive ? "pause.circle" : "play.circle")
            }
            Button(action: { analytics.toggleItemSelection(nodeId: item.nodeId) }) {
                Label(isSelected ? "Hide from Chart" : "Show in Chart", systemImage: isSelected ? "eye.slash" : "eye")
            }
            Divider()
            Button(role: .destructive, action: { analytics.removeMonitoredItem(nodeId: item.nodeId) }) {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

// MARK: - Multi-Item Chart

struct MultiItemChartView: View {
    @ObservedObject var analytics: AnalyticsManager
    let timeRange: AnalyticsView.TimeRange
    let chartMode: AnalyticsView.ChartMode

    var selectedItems: [TrackedItem] {
        analytics.monitoredItems.filter { analytics.selectedItemsForChart.contains($0.nodeId) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Real-Time Data")
                    .font(.headline)

                Spacer()

                // Legend
                HStack(spacing: 16) {
                    ForEach(selectedItems) { item in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 8, height: 8)
                            Text(item.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if selectedItems.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("Select items to display")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    )
            } else if !hasAnyData {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
                    .overlay(
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Collecting data...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                    )
            } else {
                Chart {
                    ForEach(selectedItems) { item in
                        let data = getFilteredData(for: item.nodeId)
                        ForEach(data) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Value", point.value),
                                series: .value("Item", item.displayName)
                            )
                            .foregroundStyle(item.color)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(preset: .aligned) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                    }
                }
                .chartYAxis {
                    AxisMarks(preset: .aligned) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartLegend(.hidden)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondarySystemGroupedBackground)
        )
    }

    private var hasAnyData: Bool {
        selectedItems.contains { item in
            let data = analytics.itemDataHistory[item.nodeId] ?? []
            return !data.isEmpty
        }
    }

    private func getFilteredData(for nodeId: String) -> [DataPoint] {
        let cutoff = Date().addingTimeInterval(-timeRange.seconds)
        return (analytics.itemDataHistory[nodeId] ?? []).filter { $0.timestamp > cutoff }
    }
}

// MARK: - Statistics Panel

struct StatisticsPanel: View {
    @ObservedObject var analytics: AnalyticsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics Summary")
                .font(.headline)

            if analytics.monitoredItems.isEmpty {
                Text("No data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(analytics.monitoredItems) { item in
                            if let analysis = analytics.getAnalysis(for: item.nodeId) {
                                StatRow(item: item, analysis: analysis)
                            } else {
                                PendingStatRow(item: item)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondarySystemGroupedBackground)
        )
    }
}

struct PendingStatRow: View {
    let item: TrackedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(item.color)
                    .frame(width: 8, height: 8)
                Text(item.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text("Collecting...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

struct StatRow: View {
    let item: TrackedItem
    let analysis: ItemAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(item.color)
                    .frame(width: 8, height: 8)
                Text(item.displayName)
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                Image(systemName: analysis.trend.systemImage)
                    .font(.caption)
                    .foregroundColor(analysis.trend.color)

                if analysis.isAnomaly {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            HStack(spacing: 16) {
                StatValue(label: "Min", value: analysis.min, unit: item.unit)
                StatValue(label: "Max", value: analysis.max, unit: item.unit)
                StatValue(label: "Avg", value: analysis.mean, unit: item.unit)
                StatValue(label: "σ", value: analysis.stdDev, unit: "")
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

struct StatValue: View {
    let label: String
    let value: Double
    let unit: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(String(format: "%.2f", value))
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.medium)
        }
    }
}

// MARK: - Item Detail Panel

struct ItemDetailPanel: View {
    let item: TrackedItem
    @ObservedObject var analytics: AnalyticsManager

    var analysis: ItemAnalysis? {
        analytics.getAnalysis(for: item.nodeId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(item.color)
                    .frame(width: 12, height: 12)
                Text(item.displayName)
                    .font(.headline)
                Spacer()
                Text(item.unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let analysis = analysis {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    DetailCard(title: "Current", value: String(format: "%.3f", item.currentValue), color: .blue)
                    DetailCard(title: "Range", value: String(format: "%.3f", analysis.range), color: .purple)
                    DetailCard(title: "Mean", value: String(format: "%.3f", analysis.mean), color: .green)
                    DetailCard(title: "Std Dev", value: String(format: "%.3f", analysis.stdDev), color: .orange)
                }

                HStack {
                    Text("Trend:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: analysis.trend.systemImage)
                        .foregroundColor(analysis.trend.color)
                    Text(analysis.trend.rawValue)
                        .font(.caption)
                        .foregroundColor(analysis.trend.color)

                    Spacer()

                    Text("\(analysis.dataPointCount) points")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack {
                    ProgressView()
                    Text("Collecting data...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondarySystemGroupedBackground)
        )
    }
}

struct DetailCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Comparison Panel

struct ComparisonPanel: View {
    @ObservedObject var analytics: AnalyticsManager

    var selectedItems: [TrackedItem] {
        analytics.monitoredItems.filter { analytics.selectedItemsForChart.contains($0.nodeId) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comparison")
                .font(.headline)

            if selectedItems.count < 2 {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Select 2+ items to compare")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(selectedItems) { item in
                            if let analysis = analytics.getAnalysis(for: item.nodeId) {
                                ComparisonBar(item: item, analysis: analysis, maxRange: maxRange)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondarySystemGroupedBackground)
        )
    }

    var maxRange: Double {
        selectedItems.compactMap { analytics.getAnalysis(for: $0.nodeId)?.range }.max() ?? 1
    }
}

struct ComparisonBar: View {
    let item: TrackedItem
    let analysis: ItemAnalysis
    let maxRange: Double

    var normalizedRange: Double {
        guard maxRange > 0 else { return 0 }
        return analysis.range / maxRange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.displayName)
                    .font(.caption)
                Spacer()
                Text(String(format: "%.2f - %.2f", analysis.min, analysis.max))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(item.color)
                        .frame(width: geometry.size.width * normalizedRange, height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Add Analytics Item View

struct AddAnalyticsItemView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var analytics: AnalyticsManager
    let appState: AppState

    @State private var nodeId = ""
    @State private var displayName = ""
    @State private var unit = ""
    @State private var selectedServer: OPCUAServer?

    var connectedServers: [OPCUAServer] {
        appState.servers.filter { appState.connectionManager.getConnectionStatus(for: $0) == .connected }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if connectedServers.isEmpty {
                        Text("No connected servers. Please connect to a server first.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Picker("Server", selection: $selectedServer) {
                            Text("Select a server").tag(nil as OPCUAServer?)
                            ForEach(connectedServers, id: \.id) { server in
                                Text(server.name).tag(server as OPCUAServer?)
                            }
                        }
                    }
                } header: {
                    Text("Server")
                }

                Section {
                    LabeledContent("Node ID") {
                        TextField("ns=2;s=MyVariable", text: $nodeId)
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent("Display Name") {
                        TextField("Temperature", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent("Unit") {
                        TextField("°C", text: $unit)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                } header: {
                    Text("Item Information")
                }

                Section {
                    Text("The item will start collecting data automatically once added. Values are read from the OPC UA server every second.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Note")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Monitored Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addItem()
                        dismiss()
                    }
                    .disabled(nodeId.isEmpty || displayName.isEmpty || selectedServer == nil)
                }
            }
            .onAppear {
                selectedServer = connectedServers.first
            }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 350)
        #endif
    }

    private func addItem() {
        guard let server = selectedServer else { return }

        analytics.addMonitoredItem(
            nodeId: nodeId,
            displayName: displayName,
            server: server,
            unit: unit
        )
    }
}

// MARK: - Export Data View

struct ExportDataView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var analytics: AnalyticsManager

    @State private var selectedFormat: ExportFormat = .csv
    @State private var selectedItems: Set<String> = []
    @State private var showingExporter = false
    @State private var exportDocument: DataExportDocument?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Export Format")
                }

                Section {
                    if analytics.monitoredItems.isEmpty {
                        Text("No items to export")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(analytics.monitoredItems) { item in
                            Toggle(isOn: Binding(
                                get: { selectedItems.contains(item.nodeId) },
                                set: { isOn in
                                    if isOn {
                                        selectedItems.insert(item.nodeId)
                                    } else {
                                        selectedItems.remove(item.nodeId)
                                    }
                                }
                            )) {
                                HStack {
                                    Circle()
                                        .fill(item.color)
                                        .frame(width: 8, height: 8)
                                    Text(item.displayName)
                                    Spacer()
                                    Text("\(analytics.itemDataHistory[item.nodeId]?.count ?? 0) points")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Select Items to Export")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Export Data")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        exportData()
                    }
                    .disabled(selectedItems.isEmpty)
                }
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: selectedFormat == .csv ? .commaSeparatedText : .json,
                defaultFilename: selectedFormat == .csv ? "opcua-analytics.csv" : "opcua-analytics.json"
            ) { result in
                if case .failure(let error) = result {
                    exportError = "Export failed: \(error.localizedDescription)"
                }
            }
            .alert("Export Data", isPresented: Binding<Bool>(
                get: { exportError != nil },
                set: { _ in exportError = nil }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(exportError ?? "Unknown error")
            }
            .onAppear {
                selectedItems = Set(analytics.monitoredItems.map { $0.nodeId })
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 350)
        #endif
    }

    private func exportData() {
        let nodeIds = Array(selectedItems)
        let data: Data?

        if nodeIds.count == 1, let nodeId = nodeIds.first {
            data = analytics.exportData(for: nodeId, format: selectedFormat)
        } else {
            data = analytics.exportCombinedData(for: nodeIds, format: selectedFormat)
        }

        guard let data else {
            exportError = "No data available to export"
            return
        }

        exportDocument = DataExportDocument(data: data)
        showingExporter = true
    }
}
