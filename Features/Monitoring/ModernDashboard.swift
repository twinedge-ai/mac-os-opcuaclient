import SwiftUI
import Charts
import Combine
import UniformTypeIdentifiers

struct ModernDashboard: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var dashboardManager = DashboardManager()
    @State private var selectedTimeRange = TimeRange.last24Hours
    @State private var showingWidgetGallery = false
    @State private var editMode = false
    @State private var draggedWidget: DashboardWidget?
    
    enum TimeRange: String, CaseIterable {
        case last15Minutes = "15 min"
        case last1Hour = "1 hour"
        case last24Hours = "24 hours"
        case last7Days = "7 days"
        case last30Days = "30 days"
        
        var interval: TimeInterval {
            switch self {
            case .last15Minutes: return 15 * 60
            case .last1Hour: return 60 * 60
            case .last24Hours: return 24 * 60 * 60
            case .last7Days: return 7 * 24 * 60 * 60
            case .last30Days: return 30 * 24 * 60 * 60
            }
        }
    }
    
    var body: some View {
        ZStack {
            AnimatedGradientBackground(colors: [
                Color(hex: "0F172A").opacity(0.9),
                Color(hex: "1E293B").opacity(0.9)
            ])
            
            ScrollView {
                VStack(spacing: OPCTheme.Spacing.xl) {
                    headerView
                    
                    if dashboardManager.widgets.isEmpty {
                        emptyStateView
                    } else {
                        dashboardGrid
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Dashboard")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: { editMode.toggle() }) {
                        Label(editMode ? "Done Editing" : "Edit Layout", 
                              systemImage: editMode ? "checkmark.circle" : "square.and.pencil")
                    }
                    
                    Button(action: { showingWidgetGallery = true }) {
                        Label("Add Widget", systemImage: "plus.circle")
                    }
                    
                    Divider()
                    
                    Picker("Time Range", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                }
            }
        }
        .sheet(isPresented: $showingWidgetGallery) {
            WidgetGalleryView(dashboardManager: dashboardManager)
        }
    }
    
    var headerView: some View {
        VStack(spacing: OPCTheme.Spacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: OPCTheme.Spacing.xs) {
                    Text("Welcome back")
                        .font(OPCTheme.Typography.headline)
                        .foregroundColor(OPCTheme.Colors.secondaryText)
                    
                    Text("System Overview")
                        .font(OPCTheme.Typography.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(OPCTheme.Colors.text)
                }
                
                Spacer()
                
                HStack(spacing: OPCTheme.Spacing.md) {
                    StatusIndicator(
                        title: "Servers",
                        count: appState.servers.filter { $0.status == .connected }.count,
                        total: appState.servers.count,
                        color: .green
                    )
                    
                    StatusIndicator(
                        title: "Subscriptions",
                        count: appState.subscriptions.filter { $0.isActive }.count,
                        total: appState.subscriptions.count,
                        color: .blue
                    )
                }
            }
            
            quickStatsRow
        }
    }
    
    var quickStatsRow: some View {
        HStack(spacing: OPCTheme.Spacing.md) {
            ModernMetricCard(
                title: "Active Connections",
                value: "\(appState.servers.filter { $0.status == .connected }.count)",
                subtitle: "of \(appState.servers.count) total",
                icon: "network",
                trend: .up(12.5)
            )
            
            ModernMetricCard(
                title: "Data Points",
                value: formatNumber(dashboardManager.totalDataPoints),
                subtitle: "Last \(selectedTimeRange.rawValue)",
                icon: "chart.line.uptrend.xyaxis",
                trend: .up(8.3)
            )
            
            ModernMetricCard(
                title: "Avg Response Time",
                value: "\(dashboardManager.avgResponseTime)ms",
                subtitle: "Across all servers",
                icon: "speedometer",
                trend: dashboardManager.avgResponseTime < 100 ? .up(5.2) : .down(3.1)
            )
            
            ModernMetricCard(
                title: "Alerts",
                value: "\(dashboardManager.activeAlerts)",
                subtitle: dashboardManager.activeAlerts > 0 ? "Require attention" : "All systems normal",
                icon: "bell.badge",
                trend: dashboardManager.activeAlerts > 0 ? .down(Double(dashboardManager.activeAlerts)) : .neutral
            )
        }
    }
    
    var dashboardGrid: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 350), spacing: OPCTheme.Spacing.lg)
        ], spacing: OPCTheme.Spacing.lg) {
            ForEach(dashboardManager.widgets) { widget in
                WidgetView(widget: widget, editMode: editMode)
                    .onDrag {
                        self.draggedWidget = widget
                        return NSItemProvider(object: widget.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: WidgetDropDelegate(
                        widget: widget,
                        widgets: $dashboardManager.widgets,
                        draggedWidget: $draggedWidget
                    ))
            }
        }
    }
    
    var emptyStateView: some View {
        VStack(spacing: OPCTheme.Spacing.xl) {
            Image(systemName: "square.grid.3x3.square")
                .font(.system(size: 64))
                .foregroundColor(OPCTheme.Colors.secondaryText)
            
            VStack(spacing: OPCTheme.Spacing.sm) {
                Text("No widgets added")
                    .font(OPCTheme.Typography.title2)
                    .foregroundColor(OPCTheme.Colors.text)
                
                Text("Add widgets to customize your dashboard")
                    .font(OPCTheme.Typography.body)
                    .foregroundColor(OPCTheme.Colors.secondaryText)
                
                Text("OPC UA Client")
                    .font(OPCTheme.Typography.caption2)
                    .foregroundColor(OPCTheme.Colors.tertiaryText)
                    .padding(.top, 4)
            }
            
            ModernButton(
                title: "Add Widget",
                icon: "plus.circle",
                style: .primary
            ) {
                showingWidgetGallery = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 100)
    }
    
    func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        }
        return "\(number)"
    }
}

struct StatusIndicator: View {
    let title: String
    let count: Int
    let total: Int
    let color: Color
    
    var body: some View {
        VStack(alignment: .trailing, spacing: OPCTheme.Spacing.xs) {
            HStack(spacing: OPCTheme.Spacing.xs) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .modifier(PulseAnimation(color: color))
                
                Text(title)
                    .font(OPCTheme.Typography.caption1)
                    .foregroundColor(OPCTheme.Colors.secondaryText)
            }
            
            Text("\(count)/\(total)")
                .font(OPCTheme.Typography.headline)
                .fontWeight(.semibold)
                .foregroundColor(OPCTheme.Colors.text)
        }
    }
}

struct WidgetView: View {
    let widget: DashboardWidget
    let editMode: Bool
    @State private var showingSettings = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(widget.title, systemImage: widget.icon)
                    .font(OPCTheme.Typography.headline)
                    .foregroundColor(OPCTheme.Colors.text)
                
                Spacer()
                
                if editMode {
                    Menu {
                        Button(action: { showingSettings = true }) {
                            Label("Settings", systemImage: "gear")
                        }
                        Button(role: .destructive, action: {}) {
                            Label("Remove", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(OPCTheme.Colors.secondaryText)
                    }
                }
            }
            .padding()
            
            Divider()
            
            widgetContent
                .padding()
        }
        .frame(minHeight: widget.size.height)
        .modifier(GlassCard(cornerRadius: OPCTheme.Radius.lg))
        .overlay(
            editMode ? 
            RoundedRectangle(cornerRadius: OPCTheme.Radius.lg)
                .stroke(OPCTheme.Colors.primary, lineWidth: 2)
            : nil
        )
        .scaleEffect(editMode ? 0.95 : 1.0)
        .animation(OPCTheme.Animation.spring, value: editMode)
    }
    
    @ViewBuilder
    var widgetContent: some View {
        switch widget.type {
        case .chart:
            ChartWidgetContent(widget: widget)
        case .gauge:
            GaugeWidgetContent(widget: widget)
        case .list:
            ListWidgetContent(widget: widget)
        case .metric:
            MetricWidgetContent(widget: widget)
        case .map:
            MapWidgetContent(widget: widget)
        }
    }
}

struct ChartWidgetContent: View {
    let widget: DashboardWidget
    @State private var dataPoints: [DataPoint] = []
    
    var body: some View {
        Chart(dataPoints) { point in
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Value", point.value)
            )
            .foregroundStyle(OPCTheme.Colors.Gradient.primary)
            .lineStyle(StrokeStyle(lineWidth: 2))
            
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Value", point.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        OPCTheme.Colors.primary.opacity(0.3),
                        OPCTheme.Colors.primary.opacity(0.1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(height: 200)
        .onAppear {
            generateSampleData()
        }
    }
    
    func generateSampleData() {
        let now = Date()
        dataPoints = (0..<20).map { i in
            DataPoint(
                timestamp: now.addingTimeInterval(TimeInterval(-i * 3600)),
                value: Double.random(in: 50...100)
            )
        }
    }
}

struct GaugeWidgetContent: View {
    let widget: DashboardWidget
    @State private var value: Double = 0.0
    
    var body: some View {
        VStack(spacing: OPCTheme.Spacing.md) {
            ZStack {
                Circle()
                    .stroke(OPCTheme.Colors.tertiaryBackground, lineWidth: 20)
                
                Circle()
                    .trim(from: 0, to: value / 100)
                    .stroke(
                        OPCTheme.Colors.Gradient.primary,
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: OPCTheme.Spacing.xs) {
                    Text("\(Int(value))%")
                        .font(OPCTheme.Typography.title1)
                        .fontWeight(.bold)
                    
                    Text(widget.subtitle ?? "")
                        .font(OPCTheme.Typography.caption1)
                        .foregroundColor(OPCTheme.Colors.secondaryText)
                }
            }
            .frame(width: 150, height: 150)
            .onAppear {
                withAnimation(OPCTheme.Animation.slow) {
                    value = Double.random(in: 60...95)
                }
            }
        }
    }
}

struct ListWidgetContent: View {
    let widget: DashboardWidget
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPCTheme.Spacing.sm) {
            ForEach(0..<5, id: \.self) { index in
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    
                    VStack(alignment: .leading) {
                        Text("Node \(index + 1)")
                            .font(OPCTheme.Typography.callout)
                        Text("Value: \(Int.random(in: 10...100))")
                            .font(OPCTheme.Typography.caption1)
                            .foregroundColor(OPCTheme.Colors.secondaryText)
                    }
                    
                    Spacer()
                    
                    Text("\(Int.random(in: 50...100))ms")
                        .font(OPCTheme.Typography.caption1)
                        .foregroundColor(OPCTheme.Colors.tertiaryText)
                }
                .padding(.vertical, OPCTheme.Spacing.xs)
                
                if index < 4 {
                    Divider()
                }
            }
        }
    }
}

struct MetricWidgetContent: View {
    let widget: DashboardWidget
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPCTheme.Spacing.lg) {
            HStack {
                Text("42.7")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                
                Text("°C")
                    .font(OPCTheme.Typography.title2)
                    .foregroundColor(OPCTheme.Colors.secondaryText)
                    .offset(y: -10)
            }
            
            HStack {
                Image(systemName: "arrow.up")
                    .foregroundColor(OPCTheme.Colors.success)
                Text("+2.3°C from last hour")
                    .font(OPCTheme.Typography.caption1)
                    .foregroundColor(OPCTheme.Colors.secondaryText)
            }
        }
    }
}

struct MapWidgetContent: View {
    let widget: DashboardWidget
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "3B82F6").opacity(0.1),
                            Color(hex: "10B981").opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack {
                Image(systemName: "map")
                    .font(.system(size: 48))
                    .foregroundColor(OPCTheme.Colors.primary)
                
                Text("Server Locations")
                    .font(OPCTheme.Typography.callout)
                    .foregroundColor(OPCTheme.Colors.secondaryText)
            }
        }
        .frame(height: 200)
    }
}

class DashboardManager: ObservableObject {
    @Published var widgets: [DashboardWidget] = []
    @Published var totalDataPoints = 125_430
    @Published var avgResponseTime = 87
    @Published var activeAlerts = 0
    
    init() {
        loadDefaultWidgets()
    }
    
    func loadDefaultWidgets() {
        widgets = [
            DashboardWidget(
                title: "Temperature Trend",
                type: .chart,
                icon: "chart.line.uptrend.xyaxis",
                size: .medium
            ),
            DashboardWidget(
                title: "CPU Usage",
                type: .gauge,
                icon: "cpu",
                subtitle: "Server Load",
                size: .small
            ),
            DashboardWidget(
                title: "Active Nodes",
                type: .list,
                icon: "list.bullet",
                size: .medium
            ),
            DashboardWidget(
                title: "Pressure",
                type: .metric,
                icon: "gauge",
                size: .small
            )
        ]
    }
    
    func addWidget(_ widget: DashboardWidget) {
        widgets.append(widget)
    }
    
    func removeWidget(_ widget: DashboardWidget) {
        widgets.removeAll { $0.id == widget.id }
    }
}

struct DashboardWidget: Identifiable {
    let id = UUID()
    var title: String
    var type: WidgetType
    var icon: String
    var subtitle: String? = nil
    var dataSource: String? = nil
    var refreshInterval: TimeInterval = 5.0
    var size: WidgetSize
    
    enum WidgetType {
        case chart
        case gauge
        case list
        case metric
        case map
    }
    
    enum WidgetSize {
        case small
        case medium
        case large
        
        var height: CGFloat {
            switch self {
            case .small: return 200
            case .medium: return 300
            case .large: return 400
            }
        }
    }
}

struct WidgetDropDelegate: DropDelegate {
    let widget: DashboardWidget
    @Binding var widgets: [DashboardWidget]
    @Binding var draggedWidget: DashboardWidget?
    
    func performDrop(info: DropInfo) -> Bool {
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedWidget = draggedWidget,
              draggedWidget.id != widget.id,
              let from = widgets.firstIndex(where: { $0.id == draggedWidget.id }),
              let to = widgets.firstIndex(where: { $0.id == widget.id }) else {
            return
        }
        
        withAnimation(OPCTheme.Animation.spring) {
            widgets.move(fromOffsets: IndexSet(integer: from),
                        toOffset: to > from ? to + 1 : to)
        }
    }
}

struct WidgetGalleryView: View {
    @ObservedObject var dashboardManager: DashboardManager
    @Environment(\.dismiss) private var dismiss
    
    let availableWidgets = [
        DashboardWidget(title: "Line Chart", type: .chart, icon: "chart.line.uptrend.xyaxis", size: .medium),
        DashboardWidget(title: "Gauge", type: .gauge, icon: "gauge", size: .small),
        DashboardWidget(title: "Node List", type: .list, icon: "list.bullet", size: .medium),
        DashboardWidget(title: "Metric", type: .metric, icon: "number", size: .small),
        DashboardWidget(title: "Server Map", type: .map, icon: "map", size: .large)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 150))
                ], spacing: OPCTheme.Spacing.lg) {
                    ForEach(availableWidgets) { widget in
                        WidgetPreview(widget: widget) {
                            dashboardManager.addWidget(widget)
                            dismiss()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Add Widget")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct WidgetPreview: View {
    let widget: DashboardWidget
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: OPCTheme.Spacing.md) {
                Image(systemName: widget.icon)
                    .font(.system(size: 32))
                    .foregroundColor(OPCTheme.Colors.primary)
                
                Text(widget.title)
                    .font(OPCTheme.Typography.callout)
                    .foregroundColor(OPCTheme.Colors.text)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .modifier(GlassCard(cornerRadius: OPCTheme.Radius.md))
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

#Preview {
    NavigationView {
        ModernDashboard()
            .environmentObject(AppState())
    }
}
