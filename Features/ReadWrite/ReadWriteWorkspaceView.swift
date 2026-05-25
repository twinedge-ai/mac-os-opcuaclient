import SwiftUI

struct ReadWriteWorkspaceView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var writeHistory: WriteHistoryManager
    @State private var nodeId = ""
    @State private var value = ""
    @State private var selectedOperation = ReadWriteOperation.read
    @State private var selectedType = VariantEditorType.string
    @State private var resultRows: [ReadWriteResultRow] = []
    @State private var isExecuting = false
    @State private var statusMessage = "No service call has been executed."

    init(selectedItemID: String? = nil) {
        let operation: ReadWriteOperation
        switch selectedItemID {
        case "typed-write":
            operation = .write
        case "methods":
            operation = .call
        default:
            operation = .read
        }
        _selectedOperation = State(initialValue: operation)
    }

    var body: some View {
        VStack(spacing: 0) {
            EnterpriseSectionHeader(
                title: "Read / Write",
                subtitle: "Type-aware read, write, and method-call workflow with explicit target NodeId and audit context."
            )

            GeometryReader { proxy in
                ScrollView {
                    workspaceLayout(width: proxy.size.width)
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                }
            }
        }
        .navigationTitle("Read / Write")
        .onAppear {
            if nodeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nodeId = "ns=2;s=node:hp_pump_1.flow_rate"
            }
        }
    }

    @ViewBuilder
    private func workspaceLayout(width: CGFloat) -> some View {
        if width >= 980 {
            HStack(alignment: .top, spacing: 16) {
                operationPanel
                    .frame(width: min(430, width * 0.4), alignment: .topLeading)

                resultPanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                operationPanel
                resultPanel
            }
        }
    }

    private var operationPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Operation")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Operation", selection: $selectedOperation) {
                    ForEach(ReadWriteOperation.allCases) { operation in
                        Label(operation.title, systemImage: operation.systemImage)
                            .tag(operation)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Target NodeId")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("ns=2;s=node:hp_pump_1.flow_rate", text: $nodeId)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            if selectedOperation != .read {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Variant Type")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Variant Type", selection: $selectedType) {
                        ForEach(VariantEditorType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Value")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if selectedType == .boolean {
                        Toggle("Boolean Value", isOn: Binding(
                            get: { value == "true" },
                            set: { value = $0 ? "true" : "false" }
                        ))
                    } else {
                        TextField(selectedType.placeholder, text: $value, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Safeguards")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Label("Target NodeId remains visible before execution", systemImage: "scope")
                Label("Production writes require confirmation and audit logging", systemImage: "exclamationmark.triangle")
                Label("Status code explanation is shown for failures", systemImage: "list.bullet.rectangle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button("Validate") { validateTarget() }
                    .disabled(isExecuting)

                Button(selectedOperation.actionTitle) { executeOperation() }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedNodeId.isEmpty || isExecuting)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnterpriseSectionHeader(title: "Result Detail", subtitle: "Status, source timestamp, server timestamp, and raw variant representation.")

            if isExecuting {
                ProgressView("Executing OPC UA service call...")
                    .frame(maxWidth: .infinity, maxHeight: 80)
            }

            Text(statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 10)

            ReadWriteResultGrid(rows: displayedResults)
                .frame(minHeight: 220, maxHeight: 340)

            Divider()

            EnterpriseSectionHeader(title: "Recent Writes", subtitle: "Write history is retained for review and potential revert workflows.")

            if writeHistory.entries.isEmpty {
                ContentUnavailableView("No Write History", systemImage: "clock.badge.exclamationmark", description: Text("Writes performed through this workspace will appear here."))
                    .frame(maxWidth: .infinity, maxHeight: 220)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(writeHistory.entries.prefix(8))) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.nodeId)
                                .font(.system(.caption, design: .monospaced))
                            Text("\(entry.serverName) - \(entry.value)")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var trimmedNodeId: String {
        nodeId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedResults: [ReadWriteResultRow] {
        resultRows.isEmpty ? placeholderResults : resultRows
    }

    private var placeholderResults: [ReadWriteResultRow] {
        [
            ReadWriteResultRow(field: "NodeId", value: nodeId.isEmpty ? "No node selected" : nodeId, status: .good),
            ReadWriteResultRow(field: "Variant Type", value: selectedType.rawValue, status: .good),
            ReadWriteResultRow(field: "Quality", value: "Pending service call", status: .uncertain),
            ReadWriteResultRow(field: "Source Timestamp", value: "Not read", status: .uncertain),
            ReadWriteResultRow(field: "Server Timestamp", value: "Not read", status: .uncertain)
        ]
    }

    private func validateTarget() {
        executeRead(validationOnly: true)
    }

    private func executeOperation() {
        switch selectedOperation {
        case .read:
            executeRead(validationOnly: false)
        case .write:
            executeWrite()
        case .call:
            statusMessage = "Method calls are not wired to an OPC UA service yet."
            resultRows = [
                ReadWriteResultRow(field: "NodeId", value: trimmedNodeId, status: .uncertain),
                ReadWriteResultRow(field: "Operation", value: "Call Method", status: .uncertain),
                ReadWriteResultRow(field: "Quality", value: "Not implemented", status: .uncertain)
            ]
        }
    }

    private func executeRead(validationOnly: Bool) {
        let targetNodeId = trimmedNodeId
        guard let server = activeServer else {
            statusMessage = "No connected server is selected."
            resultRows = failureRows(nodeId: targetNodeId, message: "Select and connect a server before reading.")
            return
        }

        isExecuting = true
        statusMessage = validationOnly ? "Validating target NodeId..." : "Reading target NodeId..."

        Task {
            await Task.yield()
            let value = await appState.connectionManager.readNodeValue(for: server, nodeId: targetNodeId)
            await MainActor.run {
                isExecuting = false
                if let value {
                    let now = Date()
                    statusMessage = validationOnly ? "Validation succeeded. Node is readable." : "Read succeeded."
                    resultRows = [
                        ReadWriteResultRow(field: "NodeId", value: targetNodeId, status: .good),
                        ReadWriteResultRow(field: "Value", value: value, status: .good),
                        ReadWriteResultRow(field: "Variant Type", value: inferredVariantType(for: value), status: .good),
                        ReadWriteResultRow(field: "Quality", value: OPCUAStatusCode.good.symbol, status: .good),
                        ReadWriteResultRow(field: "Server Timestamp", value: now.formatted(date: .abbreviated, time: .standard), status: .good)
                    ]
                } else {
                    statusMessage = validationOnly ? "Validation failed." : "Read failed."
                    resultRows = failureRows(nodeId: targetNodeId, message: "The selected server did not return a value for this NodeId.")
                }
            }
        }
    }

    private func executeWrite() {
        let targetNodeId = trimmedNodeId
        guard let server = activeServer else {
            statusMessage = "No connected server is selected."
            resultRows = failureRows(nodeId: targetNodeId, message: "Select and connect a server before writing.")
            return
        }

        isExecuting = true
        statusMessage = "Writing target NodeId..."

        Task {
            await Task.yield()
            let success = await appState.connectionManager.writeNodeValue(
                for: server,
                nodeId: targetNodeId,
                value: value,
                dataType: selectedType.opcuaDataType
            )
            await MainActor.run {
                isExecuting = false
                statusMessage = success ? "Write succeeded." : "Write failed."
                resultRows = [
                    ReadWriteResultRow(field: "NodeId", value: targetNodeId, status: success ? .good : .bad),
                    ReadWriteResultRow(field: "Written Value", value: value, status: success ? .good : .bad),
                    ReadWriteResultRow(field: "Variant Type", value: selectedType.opcuaDataType, status: success ? .good : .bad),
                    ReadWriteResultRow(field: "Quality", value: success ? OPCUAStatusCode.good.symbol : OPCUAStatusCode.bad.symbol, status: success ? .good : .bad)
                ]
            }
        }
    }

    private func failureRows(nodeId: String, message: String) -> [ReadWriteResultRow] {
        [
            ReadWriteResultRow(field: "NodeId", value: nodeId.isEmpty ? "No node selected" : nodeId, status: .bad),
            ReadWriteResultRow(field: "Quality", value: OPCUAStatusCode.bad.symbol, status: .bad),
            ReadWriteResultRow(field: "Diagnostic", value: message, status: .bad)
        ]
    }

    private func inferredVariantType(for value: String) -> String {
        if value == "true" || value == "false" {
            return "Boolean"
        }
        if Double(value) != nil {
            return "Double"
        }
        return "String"
    }

    private var activeServer: OPCUAServer? {
        if let selected = appState.selectedServer, appState.connectionManager.isConnected(to: selected) {
            return selected
        }
        return appState.servers.first { appState.connectionManager.isConnected(to: $0) }
    }
}

private enum ReadWriteOperation: String, CaseIterable, Identifiable {
    case read
    case write
    case call

    var id: String { rawValue }

    var title: String {
        switch self {
        case .read: return "Read"
        case .write: return "Write"
        case .call: return "Call"
        }
    }

    var actionTitle: String {
        switch self {
        case .read: return "Read"
        case .write: return "Write..."
        case .call: return "Call Method"
        }
    }

    var systemImage: String {
        switch self {
        case .read: return "arrow.down.doc"
        case .write: return "square.and.pencil"
        case .call: return "function"
        }
    }
}

private enum VariantEditorType: String, CaseIterable, Identifiable {
    case boolean = "Boolean"
    case number = "Number"
    case string = "String"
    case dateTime = "DateTime"
    case byteString = "ByteString"
    case array = "Array"

    var id: String { rawValue }

    var placeholder: String {
        switch self {
        case .boolean: return "true or false"
        case .number: return "123.45"
        case .string: return "String value"
        case .dateTime: return "2026-05-07T18:30:00Z"
        case .byteString: return "Hex or base64 bytes"
        case .array: return "[1, 2, 3]"
        }
    }

    var opcuaDataType: String {
        switch self {
        case .boolean: return "Boolean"
        case .number: return "Double"
        case .string: return "String"
        case .dateTime: return "String"
        case .byteString: return "String"
        case .array: return "String"
        }
    }
}

private struct ReadWriteResultGrid: View {
    let rows: [ReadWriteResultRow]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Field")
                    .frame(width: 150, alignment: .leading)
                Text("Value")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Status")
                    .frame(width: 130, alignment: .leading)
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
                            Text(row.field)
                                .fontWeight(.medium)
                                .frame(width: 150, alignment: .leading)

                            Text(row.value)
                                .font(.system(.caption, design: row.field == "NodeId" ? .monospaced : .default))
                                .lineLimit(3)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Label(row.status.symbol, systemImage: row.status.severity.systemImage)
                                .foregroundStyle(row.status.severity.color)
                                .frame(width: 100, alignment: .leading)
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        Divider()
                    }
                }
            }
        }
    }
}

private struct ReadWriteResultRow: Identifiable {
    let id = UUID()
    let field: String
    let value: String
    let status: OPCUAStatusCode
}
