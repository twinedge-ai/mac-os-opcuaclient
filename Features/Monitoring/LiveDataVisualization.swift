import SwiftUI
import Charts
import Combine
import UniformTypeIdentifiers

struct LiveDataVisualizationView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var dataManager = LiveDataManager()
    @State private var selectedTimeRange = TimeRange.last1Hour
    @State private var selectedVisualization = VisualizationType.multiLine
    @State private var isPaused = false
    @State private var selectedMetrics = Set<String>()
    @State private var showingMetricSelector = false
    @State private var autoScale = true
    @State private var yAxisRange = 0.0...100.0
    @State private var refreshRate = RefreshRate.fast
    @State private var showingExporter = false
    @State private var exportDocument: DataExportDocument?
    @State private var exportError: String?
    
    enum TimeRange: String, CaseIterable {
        case last1Minute = "1m"
        case last5Minutes = "5m"
        case last15Minutes = "15m"
        case last1Hour = "1h"
        case last6Hours = "6h"
        case last24Hours = "24h"
        
        var interval: TimeInterval {
            switch self {
            case .last1Minute: return 60
            case .last5Minutes: return 300
            case .last15Minutes: return 900
            case .last1Hour: return 3600
            case .last6Hours: return 21600
            case .last24Hours: return 86400
            }
        }
        
        var displayName: String {
            switch self {
            case .last1Minute: return "Last 1 minute"
            case .last5Minutes: return "Last 5 minutes"
            case .last15Minutes: return "Last 15 minutes"
            case .last1Hour: return "Last 1 hour"
            case .last6Hours: return "Last 6 hours"
            case .last24Hours: return "Last 24 hours"
            }
        }
    }
    
    enum VisualizationType: String, CaseIterable {
        case multiLine = "Multi-Line"
        case area = "Area"
        case bar = "Bar"
        case scatter = "Scatter"
        case heatmap = "Heatmap"
        case gauge = "Gauge"
        
        var icon: String {
            switch self {
            case .multiLine: return "chart.line.uptrend.xyaxis"
            case .area: return "chart.line.uptrend.xyaxis.circle"
            case .bar: return "chart.bar"
            case .scatter: return "circle.grid.cross"
            case .heatmap: return "rectangle.grid.3x2"
            case .gauge: return "gauge"
            }
        }
    }
    
    enum RefreshRate: String, CaseIterable {
        case realtime = "Real-time"
        case fast = "Fast (1s)"
        case normal = "Normal (5s)"
        case slow = "Slow (10s)"
        
        var interval: TimeInterval {
            switch self {
            case .realtime: return 0.1
            case .fast: return 1.0
            case .normal: return 5.0
            case .slow: return 10.0
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            controlBar
            
            if dataManager.selectedDataSeries.isEmpty {
                emptyStateView
            } else {
                chartContainer
            }
            
            metricsBar
        }
        .background(
            AnimatedGradientBackground(colors: [
                Color(hex: "0F172A").opacity(0.95),
                Color(hex: "1E293B").opacity(0.95)
            ])
        )
        .navigationTitle("Live Data Visualization")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            dataManager.setConnectionManager(appState.connectionManager)
            dataManager.updateAvailableMetrics(
                subscriptions: appState.subscriptions,
                servers: appState.servers
            )
            dataManager.startDataCollection(refreshRate: refreshRate.interval)
        }
        .onDisappear {
            dataManager.stopDataCollection()
        }
        .onChange(of: appState.subscriptions) { _, newValue in
            dataManager.updateAvailableMetrics(
                subscriptions: newValue,
                servers: appState.servers
            )
        }
        .onChange(of: appState.servers) { _, newValue in
            dataManager.updateAvailableMetrics(
                subscriptions: appState.subscriptions,
                servers: newValue
            )
        }
        .sheet(isPresented: $showingMetricSelector) {
            MetricSelectorView(dataManager: dataManager)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "opcua-live-data.csv"
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
    }

    private func prepareExport() {
        guard let data = dataManager.exportData() else {
            exportError = "No data available to export"
            return
        }

        exportDocument = DataExportDocument(data: data)
        showingExporter = true
    }
    
    var controlBar: some View {
        HStack(spacing: OPCTheme.Spacing.md) {
            // Time Range Selector
            Menu {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Button(range.displayName) {
                        selectedTimeRange = range
                        dataManager.updateTimeRange(range.interval)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "clock")
                    Text(selectedTimeRange.rawValue)
                }
                .font(OPCTheme.Typography.caption1)
                .foregroundColor(OPCTheme.Colors.text)
                .padding(.horizontal, OPCTheme.Spacing.md)
                .padding(.vertical, OPCTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: OPCTheme.Radius.sm)
                        .fill(OPCTheme.Colors.secondaryBackground)
                )
            }
            
            // Visualization Type Selector
            Menu {
                ForEach(VisualizationType.allCases, id: \.self) { type in
                    Button {
                        selectedVisualization = type
                    } label: {
                        Label(type.rawValue, systemImage: type.icon)
                    }
                }
            } label: {
                Image(systemName: selectedVisualization.icon)
                    .font(.system(size: 16))
                    .foregroundColor(OPCTheme.Colors.primary)
            }
            
            Spacer()
            
            // Refresh Rate
            Menu {
                ForEach(RefreshRate.allCases, id: \.self) { rate in
                    Button(rate.rawValue) {
                        refreshRate = rate
                        dataManager.updateRefreshRate(rate.interval)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text(refreshRate.rawValue)
                }
                .font(OPCTheme.Typography.caption1)
                .foregroundColor(OPCTheme.Colors.text)
            }
            
            // Pause/Play
            Button(action: { 
                isPaused.toggle()
                if isPaused {
                    dataManager.pauseDataCollection()
                } else {
                    dataManager.resumeDataCollection()
                }
            }) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16))
                    .foregroundColor(isPaused ? OPCTheme.Colors.success : OPCTheme.Colors.warning)
            }
            
            // Settings
            Menu {
                Toggle("Auto Scale", isOn: $autoScale)
                
                if !autoScale {
                    Divider()
                    Text("Y-Axis Range")
                    // Custom range controls would go here
                }
                
                Divider()
                
                Button("Export Data") {
                    prepareExport()
                }
                
                Button("Clear Data") {
                    dataManager.clearData()
                }
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 16))
                    .foregroundColor(OPCTheme.Colors.secondaryText)
            }
        }
        .padding()
        .background(OPCTheme.Colors.tertiaryBackground)
    }
    
    var chartContainer: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: OPCTheme.Spacing.lg) {
                    // Main Chart
                    mainChartView
                        .frame(height: geometry.size.height * 0.6)
                    
                    // Secondary Charts (if multiple metrics)
                    if dataManager.selectedDataSeries.count > 1 {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: OPCTheme.Spacing.md) {
                            ForEach(dataManager.selectedDataSeries.prefix(4)) { series in
                                MiniChartView(dataSeries: series)
                                    .frame(height: 150)
                            }
                        }
                    }
                    
                    // Statistics Panel
                    statisticsPanel
                }
                .padding()
            }
        }
    }
    
    @ViewBuilder
    var mainChartView: some View {
        VStack(alignment: .leading, spacing: OPCTheme.Spacing.md) {
            HStack {
                Text("Live Data Trends")
                    .font(OPCTheme.Typography.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(OPCTheme.Colors.text)
                
                Spacer()
                
                if !isPaused {
                    HStack {
                        Circle()
                            .fill(OPCTheme.Colors.success)
                            .frame(width: 8, height: 8)
                            .modifier(PulseAnimation(color: OPCTheme.Colors.success))
                        
                        Text("LIVE")
                            .font(OPCTheme.Typography.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(OPCTheme.Colors.success)
                    }
                }
            }
            
            switch selectedVisualization {
            case .multiLine:
                MultiLineChart(dataSeries: dataManager.selectedDataSeries, autoScale: autoScale)
            case .area:
                AreaChart(dataSeries: dataManager.selectedDataSeries, autoScale: autoScale)
            case .bar:
                BarChart(dataSeries: dataManager.selectedDataSeries)
            case .scatter:
                ScatterChart(dataSeries: dataManager.selectedDataSeries)
            case .heatmap:
                HeatmapChart(dataSeries: dataManager.selectedDataSeries)
            case .gauge:
                GaugeChart(dataSeries: dataManager.selectedDataSeries)
            }
        }
        .padding()
        .modifier(GlassCard(cornerRadius: OPCTheme.Radius.lg))
    }
    
    var statisticsPanel: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: OPCTheme.Spacing.md) {
            ForEach(dataManager.selectedDataSeries) { series in
                StatCard(
                    title: series.name,
                    value: series.lastValue?.value ?? 0,
                    unit: series.unit,
                    trend: series.trend,
                    color: series.color
                )
            }
        }
    }
    
    var metricsBar: some View {
        HStack {
            Button(action: { showingMetricSelector = true }) {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Add Metric")
                }
                .font(OPCTheme.Typography.caption1)
                .foregroundColor(OPCTheme.Colors.primary)
            }
            
            Spacer()
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OPCTheme.Spacing.sm) {
                    ForEach(dataManager.selectedDataSeries) { series in
                        MetricChip(
                            series: series,
                            isSelected: true,
                            onToggle: {
                                dataManager.removeDataSeries(series.id)
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(OPCTheme.Colors.secondaryBackground)
    }
    
    var emptyStateView: some View {
        VStack(spacing: OPCTheme.Spacing.xl) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 64))
                .foregroundColor(OPCTheme.Colors.tertiaryText)
            
            Text("No metrics selected")
                .font(OPCTheme.Typography.title2)
                .foregroundColor(OPCTheme.Colors.text)
            
            Text("Add some metrics to start visualizing live data")
                .font(OPCTheme.Typography.body)
                .foregroundColor(OPCTheme.Colors.secondaryText)
                .multilineTextAlignment(.center)
            
            ModernButton(
                title: "Add Metrics",
                icon: "plus.circle",
                style: .primary
            ) {
                showingMetricSelector = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Chart Views

struct MultiLineChart: View {
    let dataSeries: [DataSeries]
    let autoScale: Bool
    
    var body: some View {
        chartView
    }
    
    private var chartView: some View {
        Chart {
            ForEach(dataSeries) { series in
                ForEach(series.dataPoints) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(series.color)
                }
            }
        }
    }
}

struct AreaChart: View {
    let dataSeries: [DataSeries]
    let autoScale: Bool
    
    var body: some View {
        Chart {
            ForEach(dataSeries) { series in
                ForEach(series.dataPoints) { point in
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                series.color.opacity(0.6),
                                series.color.opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
    }
}

struct BarChart: View {
    let dataSeries: [DataSeries]
    
    var body: some View {
        Chart {
            ForEach(dataSeries) { series in
                ForEach(series.dataPoints.suffix(20)) { point in
                    BarMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(series.color)
                }
            }
        }
        .chartXAxis(.hidden)
    }
}

struct ScatterChart: View {
    let dataSeries: [DataSeries]
    
    var body: some View {
        Chart {
            ForEach(dataSeries) { series in
                ForEach(series.dataPoints) { point in
                    PointMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(series.color)
                    .symbol {
                        Circle()
                            .fill(series.color)
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
    }
}

struct HeatmapChart: View {
    let dataSeries: [DataSeries]
    
    var body: some View {
        // Simplified heatmap representation
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 10), spacing: 2) {
            ForEach(0..<100, id: \.self) { index in
                Rectangle()
                    .fill(Color.random.opacity(Double.random(in: 0.1...1.0)))
                    .frame(height: 20)
            }
        }
    }
}

struct GaugeChart: View {
    let dataSeries: [DataSeries]
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: OPCTheme.Spacing.lg) {
            ForEach(dataSeries.prefix(4)) { series in
                CircularGauge(
                    value: series.lastValue?.value ?? 0,
                    maxValue: 100,
                    color: series.color,
                    title: series.name,
                    unit: series.unit
                )
            }
        }
    }
}

struct CircularGauge: View {
    let value: Double
    let maxValue: Double
    let color: Color
    let title: String
    let unit: String
    
    var progress: Double {
        min(value / maxValue, 1.0)
    }
    
    var body: some View {
        VStack(spacing: OPCTheme.Spacing.md) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 12)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.5), color],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(OPCTheme.Animation.slow, value: progress)
                
                VStack {
                    Text("\(value, specifier: "%.1f")")
                        .font(OPCTheme.Typography.title2)
                        .fontWeight(.bold)
                        .foregroundColor(OPCTheme.Colors.text)
                    
                    Text(unit)
                        .font(OPCTheme.Typography.caption1)
                        .foregroundColor(OPCTheme.Colors.secondaryText)
                }
            }
            .frame(width: 120, height: 120)
            
            Text(title)
                .font(OPCTheme.Typography.callout)
                .foregroundColor(OPCTheme.Colors.text)
                .lineLimit(1)
        }
    }
}

struct MiniChartView: View {
    let dataSeries: DataSeries
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPCTheme.Spacing.sm) {
            HStack {
                Circle()
                    .fill(dataSeries.color)
                    .frame(width: 8, height: 8)
                
                Text(dataSeries.name)
                    .font(OPCTheme.Typography.caption1)
                    .foregroundColor(OPCTheme.Colors.text)
                
                Spacer()
                
                Text("\(dataSeries.lastValue?.value ?? 0, specifier: "%.1f")")
                    .font(OPCTheme.Typography.caption1)
                    .fontWeight(.semibold)
                    .foregroundColor(dataSeries.color)
            }
            
            Chart(dataSeries.dataPoints.suffix(20)) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(dataSeries.color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        }
        .padding()
        .modifier(GlassCard(cornerRadius: OPCTheme.Radius.md))
    }
}

struct StatCard: View {
    let title: String
    let value: Double
    let unit: String
    let trend: DataTrendType
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPCTheme.Spacing.sm) {
            HStack {
                Text(title)
                    .font(OPCTheme.Typography.caption1)
                    .foregroundColor(OPCTheme.Colors.secondaryText)
                    .lineLimit(1)
                
                Spacer()
                
                trend.icon
                    .font(.system(size: 12))
                    .foregroundColor(trend.color)
            }
            
            HStack(alignment: .firstTextBaseline) {
                Text("\(value, specifier: "%.2f")")
                    .font(OPCTheme.Typography.headline)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                
                Text(unit)
                    .font(OPCTheme.Typography.caption2)
                    .foregroundColor(OPCTheme.Colors.tertiaryText)
            }
        }
        .padding(OPCTheme.Spacing.md)
        .modifier(GlassCard(cornerRadius: OPCTheme.Radius.sm))
    }
}

struct MetricChip: View {
    let series: DataSeries
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: OPCTheme.Spacing.xs) {
                Circle()
                    .fill(series.color)
                    .frame(width: 8, height: 8)
                
                Text(series.name)
                    .font(OPCTheme.Typography.caption1)
                    .foregroundColor(OPCTheme.Colors.text)
                
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(OPCTheme.Colors.secondaryText)
            }
            .padding(.horizontal, OPCTheme.Spacing.md)
            .padding(.vertical, OPCTheme.Spacing.xs)
            .background(
                Capsule()
                    .fill(series.color.opacity(0.2))
                    .overlay(
                        Capsule()
                            .stroke(series.color, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MetricSelectorView: View {
    @ObservedObject var dataManager: LiveDataManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            VStack {
                SearchBar(text: $searchText, placeholder: "Search metrics...")
                
                List {
                    ForEach(dataManager.availableMetrics.filter { metric in
                        searchText.isEmpty || metric.name.localizedCaseInsensitiveContains(searchText)
                    }) { metric in
                        MetricRow(
                            metric: metric,
                            isSelected: dataManager.selectedDataSeries.contains { $0.id == metric.id }
                        ) {
                            dataManager.toggleDataSeries(metric)
                        }
                    }
                }
            }
            .navigationTitle("Select Metrics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct MetricRow: View {
    let metric: AvailableMetric
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(metric.name)
                    .font(OPCTheme.Typography.callout)
                
                Text(metric.description)
                    .font(OPCTheme.Typography.caption1)
                    .foregroundColor(OPCTheme.Colors.secondaryText)
            }
            
            Spacer()
            
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? OPCTheme.Colors.primary : OPCTheme.Colors.secondaryText)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
    }
}

// MARK: - Data Models and Manager

struct DataSeries: Identifiable {
    let id: String
    let name: String
    let unit: String
    let color: Color
    let nodeId: String
    let serverId: UUID
    var dataPoints: [DataPoint] = []
    
    var lastValue: DataPoint? {
        dataPoints.last
    }
    
    var trend: DataTrendType {
        guard dataPoints.count >= 2 else { return .neutral }
        let recent = dataPoints.suffix(2)
        guard let first = recent.first, let last = recent.last else { return .neutral }
        let change = last.value - first.value
        return change > 0 ? .up : change < 0 ? .down : .neutral
    }
}

struct AvailableMetric: Identifiable {
    let id: String
    let name: String
    let description: String
    let unit: String
    let nodeId: String
    let serverId: UUID
    let color: Color
}

enum DataTrendType {
    case up
    case down
    case neutral
    
    var icon: Image {
        switch self {
        case .up: return Image(systemName: "arrow.up")
        case .down: return Image(systemName: "arrow.down")
        case .neutral: return Image(systemName: "minus")
        }
    }
    
    var color: Color {
        switch self {
        case .up: return OPCTheme.Colors.success
        case .down: return OPCTheme.Colors.error
        case .neutral: return OPCTheme.Colors.secondaryText
        }
    }
}

@MainActor
class LiveDataManager: ObservableObject {
    @Published var selectedDataSeries: [DataSeries] = []
    @Published var availableMetrics: [AvailableMetric] = []
    
    private var dataGenerationTimer: Timer?
    private var isPaused = false
    private weak var connectionManager: OPCUAConnectionManager?
    private var serverLookup: [UUID: OPCUAServer] = [:]
    
    init() {}
    
    func startDataCollection(refreshRate: TimeInterval) {
        stopDataCollection()
        
        dataGenerationTimer = Timer.scheduledTimer(withTimeInterval: refreshRate, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard !self.isPaused else { return }
                await self.refreshDataPoints()
            }
        }
    }
    
    func stopDataCollection() {
        dataGenerationTimer?.invalidate()
        dataGenerationTimer = nil
    }
    
    func pauseDataCollection() {
        isPaused = true
    }
    
    func resumeDataCollection() {
        isPaused = false
    }
    
    func updateRefreshRate(_ rate: TimeInterval) {
        if dataGenerationTimer != nil {
            startDataCollection(refreshRate: rate)
        }
    }
    
    func updateTimeRange(_ interval: TimeInterval) {
        let cutoffTime = Date().addingTimeInterval(-interval)
        for index in selectedDataSeries.indices {
            selectedDataSeries[index].dataPoints.removeAll { $0.timestamp < cutoffTime }
        }
    }
    
    func toggleDataSeries(_ metric: AvailableMetric) {
        if let existingIndex = selectedDataSeries.firstIndex(where: { $0.id == metric.id }) {
            selectedDataSeries.remove(at: existingIndex)
        } else {
            let newSeries = DataSeries(
                id: metric.id,
                name: metric.name,
                unit: metric.unit,
                color: metric.color,
                nodeId: metric.nodeId,
                serverId: metric.serverId
            )
            selectedDataSeries.append(newSeries)
        }
    }
    
    func removeDataSeries(_ seriesId: String) {
        selectedDataSeries.removeAll { $0.id == seriesId }
    }
    
    func clearData() {
        for index in selectedDataSeries.indices {
            selectedDataSeries[index].dataPoints.removeAll()
        }
    }
    
    func exportData() -> Data? {
        guard !selectedDataSeries.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        var csv = "Series,NodeId,Server,Timestamp,Value,Quality\n"

        for series in selectedDataSeries {
            let serverName = serverLookup[series.serverId]?.name ?? "Unknown"
            for point in series.dataPoints {
                csv += CSVEncoder.row([
                    series.name,
                    series.nodeId,
                    serverName,
                    formatter.string(from: point.timestamp),
                    "\(point.value)",
                    point.quality.rawValue
                ]) + "\n"
            }
        }

        return csv.data(using: .utf8)
    }
    
    func setConnectionManager(_ manager: OPCUAConnectionManager) {
        connectionManager = manager
    }

    func updateAvailableMetrics(subscriptions: [Subscription], servers: [OPCUAServer]) {
        serverLookup = Dictionary(uniqueKeysWithValues: servers.map { ($0.id, $0) })

        let existingColors = Dictionary(uniqueKeysWithValues: availableMetrics.map { ($0.id, $0.color) })
        var newMetrics: [AvailableMetric] = []
        for subscription in subscriptions where subscription.isActive {
            guard let server = serverLookup[subscription.serverId] else { continue }
            for item in subscription.monitoredItems {
                let metricId = "\(subscription.serverId.uuidString)|\(item.nodeId)"
                let color = existingColors[metricId] ?? .random
                let metric = AvailableMetric(
                    id: metricId,
                    name: item.displayName,
                    description: "\(subscription.name) • \(server.name)",
                    unit: "",
                    nodeId: item.nodeId,
                    serverId: subscription.serverId,
                    color: color
                )
                newMetrics.append(metric)
            }
        }

        availableMetrics = newMetrics

        // Remove selected series that no longer exist in available metrics.
        let availableIds = Set(newMetrics.map { $0.id })
        selectedDataSeries.removeAll { !availableIds.contains($0.id) }
    }

    private func refreshDataPoints() async {
        guard let manager = connectionManager else { return }
        let timestamp = Date()

        for index in selectedDataSeries.indices {
            let series = selectedDataSeries[index]
            guard let server = serverLookup[series.serverId] else { continue }

            guard let valueString = await manager.readValue(for: server, nodeId: series.nodeId),
                  let value = Double(valueString) else {
                continue
            }

            let dataPoint = DataPoint(timestamp: timestamp, value: value, quality: .good)
            selectedDataSeries[index].dataPoints.append(dataPoint)

            if selectedDataSeries[index].dataPoints.count > 1000 {
                selectedDataSeries[index].dataPoints.removeFirst(500)
            }
        }
    }
}

extension Color {
    static var random: Color {
        Color(
            red: Double.random(in: 0...1),
            green: Double.random(in: 0...1),
            blue: Double.random(in: 0...1)
        )
    }
}
