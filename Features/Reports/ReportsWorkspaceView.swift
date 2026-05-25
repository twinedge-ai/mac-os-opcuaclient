import SwiftUI

struct ReportsWorkspaceView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedReport = EnterpriseReport.serverProfile
    @State private var showingPreview = false
    @State private var exportMessage: String?
    @State private var preparedRows: [ReportRow] = []
    @State private var preparedMarkdown = ""

    init(selectedItemID: String? = nil) {
        _selectedReport = State(initialValue: selectedItemID.flatMap(EnterpriseReport.init(rawValue:)) ?? .serverProfile)
    }

    static let sidebarItems: [EnterpriseWorkspaceItem] = EnterpriseReport.allCases.map {
        EnterpriseWorkspaceItem(
            id: $0.rawValue,
            title: $0.title,
            subtitle: $0.subtitle,
            systemImage: $0.systemImage,
            tint: $0.tint
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            EnterpriseSectionHeader(
                title: "Reports",
                subtitle: "Generate repeatable evidence for commissioning, support, security review, and customer-facing diagnostics."
            )

            HStack(spacing: 0) {
                reportNavigator
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 300)

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    EnterpriseSectionHeader(title: selectedReport.title, subtitle: selectedReport.subtitle)

                    ReportRowsGrid(rows: preparedRows)
                        .frame(minHeight: 240, maxHeight: showingPreview ? 360 : 520)

                    HStack {
                        Button("Preview") {
                            showingPreview.toggle()
                        }
                        Button("Export...") {
                            exportReport()
                        }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()

                    if showingPreview {
                        Divider()
                        ScrollView {
                            Text(preparedMarkdown)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .frame(minHeight: 160, idealHeight: 220, maxHeight: 280)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle("Reports")
        .onAppear {
            prepareReportSnapshot()
        }
        .onChange(of: selectedReport) { _, _ in
            prepareReportSnapshot()
        }
        .onChange(of: reportSnapshotKey) { _, _ in
            prepareReportSnapshot()
        }
        .alert("Report Export", isPresented: Binding(
            get: { exportMessage != nil },
            set: { _ in exportMessage = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportMessage ?? "")
        }
    }

    private var reportNavigator: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(EnterpriseReport.allCases) { report in
                    Button {
                        selectedReport = report
                    } label: {
                        Label(report.title, systemImage: report.systemImage)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedReport == report ? Color.accentColor : Color.primary)
                    .background(selectedReport == report ? Color.accentColor.opacity(0.14) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(8)
        }
        .background(.bar)
    }

    private var reportSnapshotKey: String {
        let connectedCount = appState.servers.filter { appState.connectionManager.isConnected(to: $0) }.count
        return "\(selectedReport.rawValue)-\(appState.servers.count)-\(connectedCount)-\(appState.subscriptions.count)"
    }

    private func prepareReportSnapshot() {
        let report = selectedReport
        let rows = makeReportRows(for: report)
        let markdown = makeReportMarkdown(for: report, rows: rows)

        guard selectedReport == report else { return }
        preparedRows = rows
        preparedMarkdown = markdown
    }

    private func makeReportRows(for report: EnterpriseReport) -> [ReportRow] {
        switch report {
        case .serverProfile:
            return appState.servers.map {
                ReportRow(
                    id: "\(report.rawValue)-\($0.id.uuidString)",
                    section: $0.name,
                    currentData: $0.endpoint,
                    exportFormat: "Markdown, PDF"
                )
            }
        case .securityPosture:
            return appState.servers.map {
                ReportRow(
                    id: "\(report.rawValue)-\($0.id.uuidString)",
                    section: $0.name,
                    currentData: "\($0.securityMode.rawValue) / \($0.securityPolicy.displayName)",
                    exportFormat: "Markdown, JSON"
                )
            }
        case .namespaceInventory:
            return [ReportRow(id: "\(report.rawValue)-address-space", section: "AddressSpace", currentData: "Browse cache and namespace table", exportFormat: "CSV, JSON")]
        case .subscriptionConfiguration:
            return appState.subscriptions.map {
                ReportRow(
                    id: "\(report.rawValue)-\($0.id.uuidString)",
                    section: $0.name,
                    currentData: "\($0.monitoredItems.count) monitored items",
                    exportFormat: "JSON, Markdown"
                )
            }
        case .alarmEventExport:
            return [ReportRow(id: "\(report.rawValue)-events", section: "Events", currentData: "Active and historical event stream", exportFormat: "CSV, JSON lines")]
        case .historyExport:
            return [ReportRow(id: "\(report.rawValue)-history", section: "History", currentData: "Node values, status codes, timestamps", exportFormat: "CSV, JSON lines")]
        case .diagnosticsBundle:
            return [ReportRow(id: "\(report.rawValue)-diagnostics", section: "Diagnostics", currentData: "Logs, packets, connection timeline", exportFormat: "ZIP bundle")]
        }
    }

    private func makeReportMarkdown(for report: EnterpriseReport, rows: [ReportRow]) -> String {
        let generatedAt = Date().formatted(date: .abbreviated, time: .standard)
        let rowMarkdown = rows.map { row in
            "- \(row.section): \(row.currentData) [\(row.exportFormat)]"
        }.joined(separator: "\n")

        return """
        # \(report.title)

        Generated: \(generatedAt)
        Scope: \(report.subtitle)
        Servers: \(appState.servers.count)
        Connected Servers: \(appState.servers.filter { appState.connectionManager.isConnected(to: $0) }.count)

        ## Sections
        \(rowMarkdown.isEmpty ? "- No rows available. Connect a server or configure subscriptions to populate this report." : rowMarkdown)
        """
    }

    private func exportReport() {
        do {
            let markdown = makeReportMarkdown(for: selectedReport, rows: makeReportRows(for: selectedReport))
            let safeTitle = selectedReport.title
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "/", with: "-")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(safeTitle)-\(Int(Date().timeIntervalSince1970)).md")
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            exportMessage = "Exported \(selectedReport.title) to \(url.path)"
        } catch {
            exportMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}

private struct ReportRowsGrid: View {
    let rows: [ReportRow]

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "No Report Data",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Connect a server or configure subscriptions to populate this report.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Section").frame(width: 220, alignment: .leading)
                        Text("Current Data").frame(width: 420, alignment: .leading)
                        Text("Export Format").frame(width: 160, alignment: .leading)
                        Text("Status").frame(width: 120, alignment: .leading)
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
                                    Text(row.section)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(width: 220, alignment: .leading)

                                    Text(row.currentData)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                        .frame(width: 420, alignment: .leading)

                                    Text(row.exportFormat)
                                        .lineLimit(1)
                                        .frame(width: 160, alignment: .leading)

                                    Label(row.status, systemImage: row.status == "Ready" ? "checkmark.circle" : "clock")
                                        .foregroundStyle(row.status == "Ready" ? .green : .secondary)
                                        .frame(width: 120, alignment: .leading)
                                }
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)

                                Divider()
                            }
                        }
                    }
                }
                .frame(minWidth: 970, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private enum EnterpriseReport: String, CaseIterable, Identifiable {
    case serverProfile
    case securityPosture
    case namespaceInventory
    case subscriptionConfiguration
    case alarmEventExport
    case historyExport
    case diagnosticsBundle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .serverProfile: return "Server Profile Report"
        case .securityPosture: return "Security Posture Report"
        case .namespaceInventory: return "Namespace Inventory"
        case .subscriptionConfiguration: return "Subscription Configuration"
        case .alarmEventExport: return "Alarm/Event Export"
        case .historyExport: return "History Export"
        case .diagnosticsBundle: return "Diagnostics Bundle"
        }
    }

    var subtitle: String {
        switch self {
        case .serverProfile: return "Endpoint, profile, authentication, and connection settings"
        case .securityPosture: return "Security mode, policy, trust status, and weak configuration warnings"
        case .namespaceInventory: return "Namespace table and AddressSpace inventory"
        case .subscriptionConfiguration: return "Requested configuration for restore and review"
        case .alarmEventExport: return "Operational event stream with condition fields"
        case .historyExport: return "Historical values with status and timestamp metadata"
        case .diagnosticsBundle: return "Support-ready bundle of logs, packets, and timelines"
        }
    }

    var systemImage: String {
        switch self {
        case .serverProfile: return "server.rack"
        case .securityPosture: return "lock.shield"
        case .namespaceInventory: return "square.stack.3d.up"
        case .subscriptionConfiguration: return "bell.badge"
        case .alarmEventExport: return "exclamationmark.triangle"
        case .historyExport: return "clock.arrow.circlepath"
        case .diagnosticsBundle: return "shippingbox"
        }
    }

    var tint: Color {
        switch self {
        case .serverProfile, .namespaceInventory: return .blue
        case .securityPosture: return .purple
        case .subscriptionConfiguration, .alarmEventExport: return .orange
        case .historyExport: return .green
        case .diagnosticsBundle: return .teal
        }
    }
}

private struct ReportRow: Identifiable {
    let id: String
    let section: String
    let currentData: String
    let exportFormat: String
    var status: String = "Ready"
}
