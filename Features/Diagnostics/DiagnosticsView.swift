import SwiftUI
import Charts

struct DiagnosticsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var diagnostics = DiagnosticsManager.shared
    @State private var selectedMetric = MetricType.cpu
    @State private var timeRange = TimeRange.minute
    @State private var isRecording = false
    @State private var exportMessage: String?
    private let selectedSection: DiagnosticSection

    init(selectedItemID: String? = nil) {
        self.selectedSection = DiagnosticSection(itemID: selectedItemID)
    }

    enum MetricType: String, CaseIterable {
        case cpu = "CPU Usage"
        case memory = "Memory"
        case network = "Network"
        case messages = "Messages"

        var systemImage: String {
            switch self {
            case .cpu: return "cpu"
            case .memory: return "memorychip"
            case .network: return "network"
            case .messages: return "envelope.fill"
            }
        }
    }

    enum TimeRange: String, CaseIterable {
        case minute = "1 Min"
        case fiveMinutes = "5 Min"
        case hour = "1 Hour"
        case day = "24 Hours"
    }

    enum DiagnosticSection {
        case timeline
        case serviceCalls
        case networkTrace
        case bundle

        init(itemID: String?) {
            switch itemID {
            case "service-calls":
                self = .serviceCalls
            case "network-trace":
                self = .networkTrace
            case "bundle":
                self = .bundle
            default:
                self = .timeline
            }
        }

        var title: String {
            switch self {
            case .timeline: return "Connection Timeline"
            case .serviceCalls: return "Service Calls"
            case .networkTrace: return "Network Trace"
            case .bundle: return "Diagnostics Bundle"
            }
        }

        var subtitle: String {
            switch self {
            case .timeline:
                return "Live client metrics, protocol activity, and recent diagnostic logs."
            case .serviceCalls:
                return "OPC UA service call status, message counters, protocol analyzer, and logs."
            case .networkTrace:
                return "OPC UA message flow, bytes, directions, packet timeline, and hex preview."
            case .bundle:
                return "Package logs, packets, sessions, and protocol details for support review."
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if selectedSection == .timeline {
                DiagnosticsHeader(
                    selectedMetric: $selectedMetric,
                    timeRange: $timeRange,
                    isRecording: $isRecording,
                    exportAction: exportDiagnosticsBundle
                )
            } else {
                DiagnosticSectionHeader(
                    section: selectedSection,
                    isRecording: $isRecording,
                    exportAction: exportDiagnosticsBundle
                )
            }

            diagnosticsContent
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem {
                Button {
                    exportDiagnosticsBundle()
                } label: {
                    Label("Export Bundle", systemImage: "shippingbox")
                }
            }
        }
        .alert("Diagnostics Bundle", isPresented: Binding(
            get: { exportMessage != nil },
            set: { _ in exportMessage = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportMessage ?? "")
        }
        .onAppear {
            // Log that diagnostics view was opened
            diagnostics.log("Diagnostics view opened", level: .debug, component: "UI")
        }
    }

    @ViewBuilder
    private var diagnosticsContent: some View {
        switch selectedSection {
        case .networkTrace:
            NetworkTraceView(appState: appState, diagnostics: diagnostics)
        case .serviceCalls:
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 16) {
                        ConnectionsCard(appState: appState)
                        MessagesCard(diagnostics: diagnostics)
                    }
                    ProtocolAnalyzerView(diagnostics: diagnostics)
                    SystemLogsView(diagnostics: diagnostics)
                }
                .padding()
            }
        case .bundle:
            ScrollView {
                VStack(spacing: 20) {
                    DiagnosticsBundleSummaryView(appState: appState, diagnostics: diagnostics, exportAction: exportDiagnosticsBundle)
                    ProtocolAnalyzerView(diagnostics: diagnostics)
                    SystemLogsView(diagnostics: diagnostics)
                }
                .padding()
            }
        case .timeline:
            ScrollView {
                VStack(spacing: 20) {
                    PerformanceOverview(diagnostics: diagnostics)

                    MetricsChart(
                        metric: selectedMetric,
                        timeRange: timeRange,
                        diagnostics: diagnostics
                    )

                    HStack(spacing: 16) {
                        ConnectionsCard(appState: appState)
                        MessagesCard(diagnostics: diagnostics)
                    }

                    ProtocolAnalyzerView(diagnostics: diagnostics)

                    SystemLogsView(diagnostics: diagnostics)
                }
                .padding()
            }
        }
    }

    private func exportDiagnosticsBundle() {
        do {
            let url = try DiagnosticsBundleExporter.export(appState: appState, diagnostics: diagnostics)
            exportMessage = "Exported diagnostics bundle to \(url.path)"
        } catch {
            exportMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}

struct DiagnosticSectionHeader: View {
    let section: DiagnosticsView.DiagnosticSection
    @Binding var isRecording: Bool
    let exportAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(.headline)
                Text(section.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Toggle(isOn: $isRecording) {
                Label(isRecording ? "Recording" : "Record",
                      systemImage: isRecording ? "record.circle.fill" : "record.circle")
            }
            .toggleStyle(.button)
            .foregroundColor(isRecording ? .red : .primary)

            Button(action: exportAction) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
        .padding()
        .background(Color.secondarySystemBackground)
    }
}

struct DiagnosticsHeader: View {
    @Binding var selectedMetric: DiagnosticsView.MetricType
    @Binding var timeRange: DiagnosticsView.TimeRange
    @Binding var isRecording: Bool
    let exportAction: () -> Void

    var body: some View {
        HStack {
            Picker("Metric", selection: $selectedMetric) {
                ForEach(DiagnosticsView.MetricType.allCases, id: \.self) { metric in
                    Label(metric.rawValue, systemImage: metric.systemImage)
                        .tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 400)

            Spacer()

            Picker("Time Range", selection: $timeRange) {
                ForEach(DiagnosticsView.TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.menu)

            Toggle(isOn: $isRecording) {
                Label(isRecording ? "Recording" : "Record",
                      systemImage: isRecording ? "record.circle.fill" : "record.circle")
            }
            .toggleStyle(.button)
            .foregroundColor(isRecording ? .red : .primary)

            Button(action: exportAction) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
        .padding()
        .background(Color.secondarySystemBackground)
    }
}

struct PerformanceOverview: View {
    @ObservedObject var diagnostics: DiagnosticsManager

    var body: some View {
        HStack(spacing: 16) {
            MetricCard(
                title: "CPU Usage",
                value: diagnostics.formattedCPU,
                trend: cpuTrend,
                color: .blue,
                systemImage: "cpu"
            )

            MetricCard(
                title: "Memory",
                value: diagnostics.formattedMemory,
                trend: memoryTrend,
                color: .purple,
                systemImage: "memorychip"
            )

            MetricCard(
                title: "Network I/O",
                value: formatNetworkRate(),
                trend: networkTrend,
                color: .green,
                systemImage: "network"
            )

            MetricCard(
                title: "Messages/sec",
                value: diagnostics.formattedMessagesPerSecond,
                trend: messagesTrend,
                color: .orange,
                systemImage: "envelope.fill"
            )
        }
    }

    private func formatNetworkRate() -> String {
        let totalBytes = diagnostics.networkBytesIn + diagnostics.networkBytesOut
        if totalBytes >= 1_000_000 {
            return String(format: "%.1f MB", Double(totalBytes) / 1_000_000)
        } else if totalBytes >= 1_000 {
            return String(format: "%.1f KB", Double(totalBytes) / 1_000)
        }
        return "\(totalBytes) B"
    }

    private var cpuTrend: MetricCard.Trend {
        guard diagnostics.cpuHistory.count >= 2 else { return .stable }
        let recent = diagnostics.cpuHistory.suffix(5).map { $0.1 }
        let avg = recent.reduce(0, +) / Double(recent.count)
        let current = diagnostics.cpuUsage
        if current > avg * 1.1 { return .up }
        if current < avg * 0.9 { return .down }
        return .stable
    }

    private var memoryTrend: MetricCard.Trend {
        guard diagnostics.memoryHistory.count >= 2 else { return .stable }
        let recent = diagnostics.memoryHistory.suffix(5).map { $0.1 }
        let avg = recent.reduce(0, +) / Double(recent.count)
        let current = diagnostics.memoryUsage
        if current > avg * 1.05 { return .up }
        if current < avg * 0.95 { return .down }
        return .stable
    }

    private var networkTrend: MetricCard.Trend {
        guard diagnostics.networkHistory.count >= 2 else { return .stable }
        let recent = diagnostics.networkHistory.suffix(5).map { $0.1 }
        let earlier = diagnostics.networkHistory.prefix(5).map { $0.1 }
        let recentAvg = recent.reduce(0, +) / Double(max(1, recent.count))
        let earlierAvg = earlier.reduce(0, +) / Double(max(1, earlier.count))
        if recentAvg > earlierAvg * 1.1 { return .up }
        if recentAvg < earlierAvg * 0.9 { return .down }
        return .stable
    }

    private var messagesTrend: MetricCard.Trend {
        guard diagnostics.messagesHistory.count >= 2 else { return .stable }
        let recent = diagnostics.messagesHistory.suffix(5).map { $0.1 }
        let avg = recent.reduce(0, +) / Double(recent.count)
        let current = diagnostics.messagesHistory.last?.1 ?? 0
        if current > avg * 1.1 { return .up }
        if current < avg * 0.9 { return .down }
        return .stable
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let trend: Trend
    let color: Color
    let systemImage: String

    enum Trend {
        case up, down, stable

        var systemImage: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .stable: return "arrow.right"
            }
        }

        var color: Color {
            switch self {
            case .up: return .green
            case .down: return .red
            case .stable: return .gray
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundColor(color)

                Spacer()

                Image(systemName: trend.systemImage)
                    .font(.caption)
                    .foregroundColor(trend.color)
            }

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct MetricsChart: View {
    let metric: DiagnosticsView.MetricType
    let timeRange: DiagnosticsView.TimeRange
    @ObservedObject var diagnostics: DiagnosticsManager

    var dataPoints: [(Date, Double)] {
        switch metric {
        case .cpu:
            return diagnostics.cpuHistory
        case .memory:
            return diagnostics.memoryHistory
        case .network:
            return diagnostics.networkHistory
        case .messages:
            return diagnostics.messagesHistory
        }
    }

    var chartColor: Color {
        switch metric {
        case .cpu: return .blue
        case .memory: return .purple
        case .network: return .green
        case .messages: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(metric.rawValue)
                    .font(.headline)

                Spacer()

                if dataPoints.isEmpty {
                    Text("Collecting data...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if dataPoints.isEmpty {
                // Show placeholder when no data
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 200)
                    .overlay(
                        VStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No data available yet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    )
            } else {
                Chart(dataPoints, id: \.0) { point in
                    LineMark(
                        x: .value("Time", point.0),
                        y: .value("Value", point.1)
                    )
                    .foregroundStyle(chartColor.gradient)

                    AreaMark(
                        x: .value("Time", point.0),
                        y: .value("Value", point.1)
                    )
                    .foregroundStyle(chartColor.opacity(0.1).gradient)
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(preset: .aligned) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                    }
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

struct ConnectionsCard: View {
    let appState: AppState

    var connectedServers: [OPCUAServer] {
        appState.servers.filter {
            appState.connectionManager.getConnectionStatus(for: $0) == .connected
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Active Connections", systemImage: "link")
                .font(.headline)

            Divider()

            if connectedServers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network.slash")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No active connections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(connectedServers) { server in
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                                .font(.caption)
                                .fontWeight(.medium)

                            Text(server.endpoint)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Connected")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.green)

                            Text("Port \(server.port)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
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

struct MessagesCard: View {
    @ObservedObject var diagnostics: DiagnosticsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Message Statistics", systemImage: "envelope.fill")
                .font(.headline)

            Divider()

            MessageStatRow(
                label: "Sent",
                value: formatNumber(diagnostics.messagesSent),
                rate: diagnostics.messagesSent > 0 ? diagnostics.formattedMessagesPerSecond : nil
            )
            MessageStatRow(
                label: "Received",
                value: formatNumber(diagnostics.messagesReceived),
                rate: nil
            )
            MessageStatRow(
                label: "Pending",
                value: "\(diagnostics.messagesPending)",
                rate: nil
            )
            MessageStatRow(
                label: "Errors",
                value: "\(diagnostics.messageErrors)",
                rate: nil,
                isError: diagnostics.messageErrors > 0
            )

            Divider()

            HStack {
                Text("Uptime")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(diagnostics.uptime)
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondarySystemGroupedBackground)
        )
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

struct MessageStatRow: View {
    let label: String
    let value: String
    let rate: String?
    var isError: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            HStack(spacing: 4) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundColor(isError ? .red : .primary)

                if let rate = rate {
                    Text("(\(rate))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct ProtocolAnalyzerView: View {
    @ObservedObject var diagnostics: DiagnosticsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Protocol Analyzer", systemImage: "network.badge.shield.half.filled")
                    .font(.headline)

                Spacer()

                Text("\(diagnostics.packets.count) packets")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: { diagnostics.clearPackets() }) {
                    Label("Clear", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(diagnostics.packets.isEmpty)
            }

            Divider()

            if diagnostics.packets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No packets captured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Packets will appear here when OPC UA communication occurs")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(diagnostics.packets) { packet in
                            PacketRowView(packet: packet)
                        }
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondarySystemGroupedBackground)
        )
    }
}

struct PacketRowView: View {
    let packet: PacketInfo
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: packet.direction.systemImage)
                        .foregroundColor(packet.direction == .sent ? .blue : .green)
                        .font(.caption)

                    Text(packet.type)
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(width: 50, alignment: .leading)

                    Text(packet.timestamp, format: .dateTime.hour().minute().second().secondFraction(.fractional(3)))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(packet.size) bytes")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(packet.hexDump)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
                    .textSelection(.enabled)
            }
        }
    }
}

struct NetworkTraceView: View {
    let appState: AppState
    @ObservedObject var diagnostics: DiagnosticsManager
    @AppStorage("opcua.client.networkTraceRelay.enabled") private var isByteRelayEnabled = false

    private var connectedServers: [OPCUAServer] {
        appState.servers.filter { appState.connectionManager.isConnected(to: $0) }
    }

    private var packetsInTimelineOrder: [PacketInfo] {
        diagnostics.packets.reversed()
    }

    private var maxPacketSize: Double {
        Double(diagnostics.packets.map(\.size).max() ?? 1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("OPC UA Network Trace", systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.title2.weight(.semibold))
                        Text("Message flow is captured from the local TCP relay when available, with OPC UA Binary frames, byte counts, directions, and hex previews.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle(isOn: $isByteRelayEnabled) {
                        Label("Byte Relay", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Button {
                        diagnostics.clearPackets()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(diagnostics.packets.isEmpty)
                }

                if connectedServers.isEmpty {
                    Label("No active OPC UA session. Connect to a server to capture protocol traffic.", systemImage: "network.slash")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }

                HStack(spacing: 12) {
                    TraceMetricTile(title: "Inbound", value: diagnostics.formattedNetworkIn, systemImage: "arrow.down.circle", tint: .green)
                    TraceMetricTile(title: "Outbound", value: diagnostics.formattedNetworkOut, systemImage: "arrow.up.circle", tint: .blue)
                    TraceMetricTile(title: "Packets", value: "\(diagnostics.packets.count)", systemImage: "list.bullet.rectangle", tint: .purple)
                    TraceMetricTile(title: "Errors", value: "\(diagnostics.messageErrors)", systemImage: "exclamationmark.triangle", tint: diagnostics.messageErrors > 0 ? .red : .secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Byte Flow")
                        .font(.headline)

                    if diagnostics.packets.isEmpty {
                        ContentUnavailableView(
                            "No Packets Captured",
                            systemImage: "waveform.path.ecg",
                            description: Text("Connect, browse, read, write, or subscribe to generate OPC UA trace entries.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Client")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Server")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(packetsInTimelineOrder) { packet in
                                PacketFlowRow(packet: packet, maxPacketSize: maxPacketSize)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 10))

                HStack(alignment: .top, spacing: 16) {
                    ProtocolBreakdownView(packets: diagnostics.packets)
                    PacketHexTableView(packets: diagnostics.packets)
                }
            }
            .padding()
        }
    }
}

private struct TraceMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .font(.title3)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.25)))
    }
}

private struct PacketFlowRow: View {
    let packet: PacketInfo
    let maxPacketSize: Double

    private var normalizedWidth: CGFloat {
        let ratio = Double(packet.size) / max(1, maxPacketSize)
        return CGFloat(120 + ratio * 280)
    }

    var body: some View {
        HStack(spacing: 10) {
            if packet.direction == .sent {
                flowLabel(isLeading: true)
                flowLine
                Spacer(minLength: 20)
            } else {
                Spacer(minLength: 20)
                flowLine
                flowLabel(isLeading: false)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(packet.type) \(packet.direction == .sent ? "sent" : "received"), \(packet.size) bytes")
    }

    private var flowLine: some View {
        HStack(spacing: 6) {
            if packet.direction == .received {
                Image(systemName: "arrow.left")
            }

            Capsule()
                .fill(packet.direction == .sent ? .blue : .green)
                .frame(width: normalizedWidth, height: 8)

            if packet.direction == .sent {
                Image(systemName: "arrow.right")
            }
        }
        .foregroundStyle(packet.direction == .sent ? .blue : .green)
        .frame(maxWidth: .infinity, alignment: packet.direction == .sent ? .leading : .trailing)
    }

    private func flowLabel(isLeading: Bool) -> some View {
        VStack(alignment: isLeading ? .leading : .trailing, spacing: 2) {
            Text(packet.type)
                .font(.caption.weight(.semibold))
            Text("\(packet.size) bytes")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(packet.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 120, alignment: isLeading ? .leading : .trailing)
    }
}

private struct ProtocolBreakdownView: View {
    let packets: [PacketInfo]

    private var rows: [(type: String, label: String, count: Int, bytes: Int)] {
        Dictionary(grouping: packets, by: \.type)
            .map { type, packets in
                (type, protocolLabel(for: type), packets.count, packets.reduce(0) { $0 + $1.size })
            }
            .sorted { $0.type < $1.type }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Protocol Breakdown")
                .font(.headline)

            if rows.isEmpty {
                Text("No protocol messages recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("Type").font(.caption.weight(.semibold))
                        Text("Meaning").font(.caption.weight(.semibold))
                        Text("Count").font(.caption.weight(.semibold))
                        Text("Bytes").font(.caption.weight(.semibold))
                    }
                    Divider()
                    ForEach(rows, id: \.type) { row in
                        GridRow {
                            Text(row.type).font(.caption.monospaced().weight(.semibold))
                            Text(row.label).font(.caption)
                            Text("\(row.count)").font(.caption.monospacedDigit())
                            Text(formatBytes(row.bytes)).font(.caption.monospacedDigit())
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private func protocolLabel(for type: String) -> String {
        let baseType = type.split(separator: "/").first.map(String.init) ?? type
        switch baseType {
        case "HEL": return "Hello"
        case "ACK": return "Acknowledge"
        case "ERR": return "Protocol error"
        case "RHE": return "ReverseHello"
        case "OPN": return "OpenSecureChannel"
        case "MSG": return "Secure conversation"
        case "READ": return "Read service"
        case "WRITE": return "Write service"
        case "CLO": return "CloseSecureChannel"
        case "TCP": return "Unframed TCP bytes"
        default: return "Service message"
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1_000_000 { return String(format: "%.1f MB", Double(bytes) / 1_000_000) }
        if bytes >= 1_000 { return String(format: "%.1f KB", Double(bytes) / 1_000) }
        return "\(bytes) B"
    }
}

private struct PacketHexTableView: View {
    let packets: [PacketInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Packet Hex Preview")
                .font(.headline)

            if packets.isEmpty {
                Text("No hex payload preview available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(packets.prefix(12)) { packet in
                        HStack(alignment: .firstTextBaseline) {
                            Text(packet.type)
                                .font(.caption.monospaced().weight(.semibold))
                                .frame(width: 48, alignment: .leading)
                            Text(packet.direction == .sent ? "TX" : "RX")
                                .font(.caption2.monospaced())
                                .foregroundStyle(packet.direction == .sent ? .blue : .green)
                                .frame(width: 28, alignment: .leading)
                            Text(packet.hexDump)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct DiagnosticsBundleSummaryView: View {
    let appState: AppState
    @ObservedObject var diagnostics: DiagnosticsManager
    let exportAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics Bundle")
                .font(.title3.weight(.semibold))
            Text("Package connection profiles, active session status, logs, packet traces, and protocol counters for support handoff.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Servers")
                    Text("\(appState.servers.count)")
                }
                GridRow {
                    Text("Active Sessions")
                    Text("\(appState.servers.filter { appState.connectionManager.isConnected(to: $0) }.count)")
                }
                GridRow {
                    Text("Logs")
                    Text("\(diagnostics.logs.count)")
                }
                GridRow {
                    Text("Packets")
                    Text("\(diagnostics.packets.count)")
                }
            }
            .font(.callout.monospacedDigit())

            Button(action: exportAction) {
                Label("Export Bundle", systemImage: "shippingbox")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SystemLogsView: View {
    @ObservedObject var diagnostics: DiagnosticsManager
    @State private var filterLevel: LogLevel = .all

    var filteredLogs: [LogEntry] {
        if filterLevel == .all {
            return diagnostics.logs
        }
        return diagnostics.logs.filter { $0.level == filterLevel }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("System Logs", systemImage: "doc.text.fill")
                    .font(.headline)

                Spacer()

                Text("\(filteredLogs.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Level", selection: $filterLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)

                Button(action: { diagnostics.clearLogs() }) {
                    Label("Clear", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(diagnostics.logs.isEmpty)
            }

            Divider()

            if filteredLogs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No log entries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredLogs) { log in
                            LogRowView(log: log)
                        }
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondarySystemGroupedBackground)
        )
    }
}

struct LogRowView: View {
    let log: LogEntry

    var levelColor: Color {
        switch log.level {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .debug: return .gray
        case .all: return .primary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(levelColor)
                .frame(width: 6, height: 6)
                .offset(y: 5)

            Text(log.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            Text("[\(log.component)]")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(levelColor)
                .frame(width: 80, alignment: .leading)

            Text(log.message)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()
        }
        .padding(.vertical, 2)
    }
}
