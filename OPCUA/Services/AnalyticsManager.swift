import Foundation
import Combine
import SwiftUI

@MainActor
class AnalyticsManager: ObservableObject {
    static let shared = AnalyticsManager()

    // MARK: - Published Properties

    /// All monitored items being tracked
    @Published var monitoredItems: [TrackedItem] = []

    /// Historical data for each monitored item (keyed by nodeId)
    @Published var itemDataHistory: [String: [DataPoint]] = [:]

    /// Items selected for comparison in charts
    @Published var selectedItemsForChart: Set<String> = []

    /// Statistical analysis results
    @Published var analysisResults: [String: ItemAnalysis] = [:]

    // MARK: - Configuration

    /// Maximum data points to keep per item
    var maxDataPoints: Int = 1000

    /// Data retention period in seconds
    var retentionPeriod: TimeInterval = 3600 // 1 hour

    /// Update interval in seconds
    var updateInterval: TimeInterval = 1.0

    private var updateTimer: Timer?
    private var diagnostics: DiagnosticsManager { DiagnosticsManager.shared }

    /// Reference to connection manager (set from AppState)
    weak var connectionManager: OPCUAConnectionManager?

    // MARK: - Initialization

    private init() {}

    // MARK: - Data Collection

    func startDataCollection() {
        guard updateTimer == nil else { return }

        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateMonitoredItemValues()
            }
        }

        diagnostics.log("Analytics data collection started", level: .info, component: "Analytics")
    }

    func stopDataCollection() {
        updateTimer?.invalidate()
        updateTimer = nil
        diagnostics.log("Analytics data collection stopped", level: .info, component: "Analytics")
    }

    private func updateMonitoredItemValues() async {
        guard let connectionManager = connectionManager else { return }

        let now = Date()

        for item in monitoredItems where item.isActive {
            // Get real value from OPC UA server
            guard let server = getServer(for: item.serverId),
                  connectionManager.getConnectionStatus(for: server) == .connected else {
                // Mark item as disconnected
                if let index = monitoredItems.firstIndex(where: { $0.nodeId == item.nodeId }) {
                    monitoredItems[index].isConnected = false
                }
                continue
            }

            // Read actual value from OPC UA
            if let valueString = await connectionManager.readValue(for: server, nodeId: item.nodeId),
               let value = Double(valueString) {

                let dataPoint = DataPoint(timestamp: now, value: value, quality: .good)

                // Append to history
                var history = itemDataHistory[item.nodeId] ?? []
                history.append(dataPoint)

                // Trim old data
                let cutoff = now.addingTimeInterval(-retentionPeriod)
                history = history.filter { $0.timestamp > cutoff }

                // Limit total points
                if history.count > maxDataPoints {
                    history = Array(history.suffix(maxDataPoints))
                }

                itemDataHistory[item.nodeId] = history

                // Update current value
                if let index = monitoredItems.firstIndex(where: { $0.nodeId == item.nodeId }) {
                    monitoredItems[index].currentValue = value
                    monitoredItems[index].lastUpdate = now
                    monitoredItems[index].isConnected = true
                }

                // Update analysis
                updateAnalysis(for: item.nodeId)

                // Log packet for diagnostics
                diagnostics.recordPacket(type: "READ", direction: .received, size: 16, data: nil)
            } else {
                // Value read failed or not a number
                if let index = monitoredItems.firstIndex(where: { $0.nodeId == item.nodeId }) {
                    monitoredItems[index].isConnected = false
                }
            }
        }
    }

    private func getServer(for serverId: UUID) -> OPCUAServer? {
        // Find the server from monitored items (server is stored on each TrackedItem)
        return monitoredItems.first { $0.serverId == serverId }?.server
    }

    // MARK: - Item Management

    func addMonitoredItem(nodeId: String, displayName: String, server: OPCUAServer, unit: String = "", initialValue: Double? = nil) {
        guard !monitoredItems.contains(where: { $0.nodeId == nodeId }) else {
            diagnostics.log("Item \(nodeId) already being monitored", level: .warning, component: "Analytics")
            return
        }

        let now = Date()
        var item = TrackedItem(
            nodeId: nodeId,
            displayName: displayName,
            server: server,
            unit: unit,
            color: getNextColor()
        )
        if let initialValue {
            item.currentValue = initialValue
            item.lastUpdate = now
        }

        monitoredItems.append(item)
        itemDataHistory[nodeId] = initialValue.map { [DataPoint(timestamp: now, value: $0, quality: .good)] } ?? []
        selectedItemsForChart.insert(nodeId)

        // Start data collection if not already running
        if updateTimer == nil {
            startDataCollection()
        }

        diagnostics.log("Started monitoring \(displayName) (\(nodeId))", level: .info, component: "Analytics")
    }

    func removeMonitoredItem(nodeId: String) {
        monitoredItems.removeAll { $0.nodeId == nodeId }
        itemDataHistory.removeValue(forKey: nodeId)
        selectedItemsForChart.remove(nodeId)
        analysisResults.removeValue(forKey: nodeId)

        // Stop data collection if no items left
        if monitoredItems.isEmpty {
            stopDataCollection()
        }

        diagnostics.log("Stopped monitoring \(nodeId)", level: .info, component: "Analytics")
    }

    func toggleItemSelection(nodeId: String) {
        if selectedItemsForChart.contains(nodeId) {
            selectedItemsForChart.remove(nodeId)
        } else {
            selectedItemsForChart.insert(nodeId)
        }
    }

    func toggleItemActive(nodeId: String) {
        if let index = monitoredItems.firstIndex(where: { $0.nodeId == nodeId }) {
            monitoredItems[index].isActive.toggle()
        }
    }

    // MARK: - Analysis

    private func updateAnalysis(for nodeId: String) {
        guard let history = itemDataHistory[nodeId], history.count >= 2 else { return }

        let values = history.map { $0.value }
        let count = Double(values.count)

        let min = values.min() ?? 0
        let max = values.max() ?? 0
        let sum = values.reduce(0, +)
        let mean = sum / count

        // Standard deviation
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / count
        let stdDev = sqrt(variance)

        // Rate of change (last 10 samples)
        let recentValues = Array(values.suffix(10))
        var rateOfChange: Double = 0
        if recentValues.count >= 2,
           let firstRecentValue = recentValues.first,
           let lastRecentValue = recentValues.last {
            rateOfChange = (lastRecentValue - firstRecentValue) / Double(recentValues.count - 1)
        }

        // Trend detection
        let trend: Trend
        if rateOfChange > stdDev * 0.1 {
            trend = .increasing
        } else if rateOfChange < -stdDev * 0.1 {
            trend = .decreasing
        } else {
            trend = .stable
        }

        // Anomaly detection (simple: value > mean + 2*stdDev)
        let lastValue = values.last ?? mean
        let isAnomaly = abs(lastValue - mean) > 2 * stdDev

        analysisResults[nodeId] = ItemAnalysis(
            min: min,
            max: max,
            mean: mean,
            stdDev: stdDev,
            rateOfChange: rateOfChange,
            trend: trend,
            isAnomaly: isAnomaly,
            dataPointCount: values.count,
            lastUpdated: Date()
        )
    }

    func getAnalysis(for nodeId: String) -> ItemAnalysis? {
        return analysisResults[nodeId]
    }

    // MARK: - Data Export

    func exportData(for nodeId: String, format: ExportFormat) -> Data? {
        guard let history = itemDataHistory[nodeId],
              let item = monitoredItems.first(where: { $0.nodeId == nodeId }) else {
            return nil
        }

        switch format {
        case .csv:
            return exportAsCSV(item: item, history: history)
        case .json:
            return exportAsJSON(item: item, history: history)
        }
    }

    func exportCombinedData(for nodeIds: [String], format: ExportFormat, since: Date? = nil) -> Data? {
        let items = monitoredItems.filter { nodeIds.contains($0.nodeId) }
        guard !items.isEmpty else { return nil }

        switch format {
        case .csv:
            return exportCombinedAsCSV(items: items, since: since)
        case .json:
            return exportCombinedAsJSON(items: items, since: since)
        }
    }

    private func exportAsCSV(item: TrackedItem, history: [DataPoint]) -> Data? {
        var csv = "Timestamp,Value,Quality\n"
        let formatter = ISO8601DateFormatter()

        for point in history {
            csv += CSVEncoder.row([
                formatter.string(from: point.timestamp),
                "\(point.value)",
                point.quality.rawValue
            ]) + "\n"
        }

        return csv.data(using: .utf8)
    }

    private func exportCombinedAsCSV(items: [TrackedItem], since: Date?) -> Data? {
        let formatter = ISO8601DateFormatter()
        var csv = "Item,NodeId,Server,Unit,Timestamp,Value,Quality\n"

        for item in items {
            let history = filteredHistory(for: item.nodeId, since: since)
            for point in history {
                csv += CSVEncoder.row([
                    item.displayName,
                    item.nodeId,
                    item.server.name,
                    item.unit,
                    formatter.string(from: point.timestamp),
                    "\(point.value)",
                    point.quality.rawValue
                ]) + "\n"
            }
        }

        return csv.data(using: .utf8)
    }

    private func exportCombinedAsJSON(items: [TrackedItem], since: Date?) -> Data? {
        let formatter = ISO8601DateFormatter()
        let exportedAt = formatter.string(from: Date())
        let payload = items.map { item -> [String: Any] in
            let history = filteredHistory(for: item.nodeId, since: since)
            var itemPayload: [String: Any] = [
                "nodeId": item.nodeId,
                "displayName": item.displayName,
                "unit": item.unit,
                "serverName": item.server.name,
                "exportedAt": exportedAt,
                "dataPoints": history.map { point in
                    [
                        "timestamp": formatter.string(from: point.timestamp),
                        "value": point.value,
                        "quality": point.quality.rawValue
                    ]
                }
            ]
            if let result = analysisResults[item.nodeId] {
                itemPayload["analysis"] = [
                    "min": result.min,
                    "max": result.max,
                    "mean": result.mean,
                    "stdDev": result.stdDev,
                    "rateOfChange": result.rateOfChange,
                    "trend": result.trend.rawValue,
                    "isAnomaly": result.isAnomaly,
                    "dataPointCount": result.dataPointCount,
                    "lastUpdated": formatter.string(from: result.lastUpdated)
                ]
            }
            return itemPayload
        }

        return try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
    }

    private func filteredHistory(for nodeId: String, since: Date?) -> [DataPoint] {
        let history = itemDataHistory[nodeId] ?? []
        guard let since else { return history }
        return history.filter { $0.timestamp >= since }
    }

    private func exportAsJSON(item: TrackedItem, history: [DataPoint]) -> Data? {
        let formatter = ISO8601DateFormatter()

        let exportData: [String: Any] = [
            "nodeId": item.nodeId,
            "displayName": item.displayName,
            "unit": item.unit,
            "serverName": item.server.name,
            "exportedAt": formatter.string(from: Date()),
            "dataPoints": history.map { point in
                [
                    "timestamp": formatter.string(from: point.timestamp),
                    "value": point.value,
                    "quality": point.quality.rawValue
                ]
            }
        ]

        return try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }

    // MARK: - Helpers

    private var colorIndex = 0
    private let chartColors: [Color] = [
        .blue, .green, .orange, .purple, .red, .cyan, .pink, .yellow, .mint, .indigo
    ]

    private func getNextColor() -> Color {
        let color = chartColors[colorIndex % chartColors.count]
        colorIndex += 1
        return color
    }

    func clearAllData() {
        for nodeId in itemDataHistory.keys {
            itemDataHistory[nodeId] = []
        }
        analysisResults.removeAll()
        diagnostics.log("Cleared all analytics data", level: .info, component: "Analytics")
    }

    func clearAllItems() {
        stopDataCollection()
        monitoredItems.removeAll()
        itemDataHistory.removeAll()
        selectedItemsForChart.removeAll()
        analysisResults.removeAll()
        colorIndex = 0
    }

    /// Check if there are any connected servers with monitored items
    var hasActiveConnections: Bool {
        guard let connectionManager = connectionManager else { return false }
        return monitoredItems.contains { item in
            connectionManager.getConnectionStatus(for: item.server) == .connected
        }
    }
}

// MARK: - Supporting Types

struct TrackedItem: Identifiable, Hashable {
    let id = UUID()
    let nodeId: String
    let displayName: String
    let server: OPCUAServer
    var unit: String
    var color: Color
    var isActive: Bool = true
    var isConnected: Bool = true
    var currentValue: Double = 0
    var lastUpdate: Date?

    var serverId: UUID { server.id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TrackedItem, rhs: TrackedItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct ItemAnalysis {
    let min: Double
    let max: Double
    let mean: Double
    let stdDev: Double
    let rateOfChange: Double
    let trend: Trend
    let isAnomaly: Bool
    let dataPointCount: Int
    let lastUpdated: Date

    var range: Double { max - min }
}

enum Trend: String {
    case increasing = "Increasing"
    case decreasing = "Decreasing"
    case stable = "Stable"

    var systemImage: String {
        switch self {
        case .increasing: return "arrow.up.right"
        case .decreasing: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    var color: Color {
        switch self {
        case .increasing: return .green
        case .decreasing: return .red
        case .stable: return .gray
        }
    }
}

enum ExportFormat: String, CaseIterable {
    case csv = "CSV"
    case json = "JSON"

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        }
    }
}
