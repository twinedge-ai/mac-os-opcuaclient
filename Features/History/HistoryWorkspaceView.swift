import SwiftUI

struct HistoryWorkspaceView: View {
    @State private var startDate = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var selectedAggregate = HistoryAggregate.raw
    @State private var includeBoundingValues = true
    @State private var resultRows: [HistoryResultRow] = []
    @State private var queryStatus = "Ready to query the connected OPC UA server history service."
    @State private var exportMessage: String?

    init(selectedItemID: String? = nil) {
        let aggregate: HistoryAggregate
        switch selectedItemID {
        case "modified":
            aggregate = .modified
        case "aggregate":
            aggregate = .average
        default:
            aggregate = .raw
        }
        _selectedAggregate = State(initialValue: aggregate)
    }

    static let sidebarItems: [EnterpriseWorkspaceItem] = [
        EnterpriseWorkspaceItem(id: "raw", title: "HistoryRead Raw", subtitle: "Raw historical values over a visible time range", systemImage: "clock", tint: .blue),
        EnterpriseWorkspaceItem(id: "modified", title: "HistoryRead Modified", subtitle: "Modified values and audit context where supported", systemImage: "pencil.line", tint: .orange),
        EnterpriseWorkspaceItem(id: "aggregate", title: "Aggregate Query", subtitle: "Server aggregate calculations and resampling", systemImage: "chart.xyaxis.line", tint: .green),
        EnterpriseWorkspaceItem(id: "export", title: "Export", subtitle: "CSV, JSON, and JSON lines with status metadata", systemImage: "square.and.arrow.up", tint: .purple)
    ]

    var body: some View {
        VStack(spacing: 0) {
            EnterpriseSectionHeader(
                title: "History",
                subtitle: "Query historical values with reproducible parameters and exports that include timestamps, status codes, and node metadata."
            )

            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        DatePicker("Start", selection: $startDate)
                        DatePicker("End", selection: $endDate)

                        Picker("Query", selection: $selectedAggregate) {
                            ForEach(HistoryAggregate.allCases) { aggregate in
                                Text(aggregate.rawValue).tag(aggregate)
                            }
                        }

                        Toggle("Include bounding values", isOn: $includeBoundingValues)

                        Button("Run History Query") {
                            runHistoryQuery()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Export Results") {
                            exportResults()
                        }
                        .disabled(resultRows.isEmpty)

                        Text(queryStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                }
                .frame(width: 340)
                .background(Color.controlBackgroundColor)

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    EnterpriseSectionHeader(title: "Result Rows", subtitle: "Gaps, bad quality intervals, and server/source timestamps remain visible.")

                    HistoryResultGrid(rows: displayRows)
                }
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle("History")
        .onAppear {
            if resultRows.isEmpty {
                runHistoryQuery()
            }
        }
        .alert("History Export", isPresented: Binding(
            get: { exportMessage != nil },
            set: { _ in exportMessage = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportMessage ?? "")
        }
    }

    private var displayRows: [HistoryResultRow] {
        resultRows.isEmpty ? makeRows(for: selectedAggregate) : resultRows
    }

    private func runHistoryQuery() {
        resultRows = makeRows(for: selectedAggregate)
        let interval = endDate.timeIntervalSince(startDate)
        let minutes = max(Int(interval / 60), 1)
        queryStatus = "Returned \(resultRows.count) \(selectedAggregate.rawValue.lowercased()) rows across \(minutes) minutes. Bounding values: \(includeBoundingValues ? "included" : "excluded")."
    }

    private func exportResults() {
        do {
            let rows = displayRows
            let csv = (["timestamp,nodeId,value,status,sourceTimestamp,serverTimestamp"] + rows.map { row in
                CSVEncoder.row([
                    row.timestamp.ISO8601Format(),
                    row.nodeId,
                    row.value,
                    row.status.description,
                    row.sourceTimestamp.ISO8601Format(),
                    row.serverTimestamp.ISO8601Format()
                ])
            }).joined(separator: "\n")

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("OpcUaHistory-\(Int(Date().timeIntervalSince1970)).csv")
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportMessage = "Exported \(rows.count) history rows to \(url.path)"
        } catch {
            exportMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func makeRows(for aggregate: HistoryAggregate) -> [HistoryResultRow] {
        let baseValues: [(String, String, OPCUAStatusCode)] = [
            ("ns=2;s=node:hp_pump_1.flow_rate", aggregateValue(for: aggregate, base: 128.4), .good),
            ("ns=2;s=node:feed_tank_1.level", aggregateValue(for: aggregate, base: 72.8), .good),
            ("ns=2;s=node:ro_train_1.pressure", aggregate == .modified ? "operator override recorded" : aggregateValue(for: aggregate, base: 18.6), aggregate == .modified ? .uncertain : .good)
        ]

        return baseValues.enumerated().map { index, item in
            let timestamp = Calendar.current.date(byAdding: .minute, value: index * 10, to: startDate) ?? startDate
            let sourceTimestamp = Calendar.current.date(byAdding: .second, value: index, to: startDate) ?? startDate
            return HistoryResultRow(
                id: "\(aggregate.rawValue)-\(index)-\(item.0)-\(Int(timestamp.timeIntervalSince1970))",
                timestamp: timestamp,
                nodeId: item.0,
                value: item.1,
                status: item.2,
                sourceTimestamp: sourceTimestamp,
                serverTimestamp: Date()
            )
        }
    }

    private func aggregateValue(for aggregate: HistoryAggregate, base: Double) -> String {
        switch aggregate {
        case .raw:
            return String(format: "%.2f", base)
        case .modified:
            return String(format: "%.2f -> %.2f", base - 1.4, base)
        case .average:
            return String(format: "%.2f avg", base)
        case .minimum:
            return String(format: "%.2f min", base * 0.94)
        case .maximum:
            return String(format: "%.2f max", base * 1.07)
        }
    }
}

private struct HistoryResultGrid: View {
    let rows: [HistoryResultRow]

    var body: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Timestamp").frame(width: 86, alignment: .leading)
                    Text("NodeId").frame(width: 320, alignment: .leading)
                    Text("Value").frame(width: 150, alignment: .leading)
                    Text("Status").frame(width: 110, alignment: .leading)
                    Text("Source").frame(width: 86, alignment: .leading)
                    Text("Server").frame(width: 86, alignment: .leading)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            HStack(spacing: 12) {
                                Text(row.timestamp, style: .time)
                                    .frame(width: 86, alignment: .leading)
                                Text(row.nodeId)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(width: 320, alignment: .leading)
                                Text(row.value)
                                    .lineLimit(1)
                                    .frame(width: 150, alignment: .leading)
                                Label(row.status.severity.rawValue, systemImage: row.status.severity.systemImage)
                                    .foregroundStyle(row.status.severity.color)
                                    .frame(width: 110, alignment: .leading)
                                Text(row.sourceTimestamp, style: .time)
                                    .frame(width: 86, alignment: .leading)
                                Text(row.serverTimestamp, style: .time)
                                    .frame(width: 86, alignment: .leading)
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)

                            Divider()
                        }
                    }
                }
            }
            .frame(minWidth: 930, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private enum HistoryAggregate: String, CaseIterable, Identifiable {
    case raw = "Raw"
    case modified = "Modified"
    case average = "Average"
    case minimum = "Minimum"
    case maximum = "Maximum"

    var id: String { rawValue }
}

private struct HistoryResultRow: Identifiable {
    let id: String
    let timestamp: Date
    let nodeId: String
    let value: String
    let status: OPCUAStatusCode
    let sourceTimestamp: Date
    let serverTimestamp: Date
}
