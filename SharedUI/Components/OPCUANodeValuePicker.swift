import SwiftUI

struct OPCUANodeValuePicker: View {
    let server: OPCUAServer
    var appState: AppState
    var title = "Select Node"
    var instruction = "Expand folders and choose a Variable node with a readable value."
    var confirmTitle = "Use Node"
    var requiresReadableValue = true
    var requiresNumericValue = false
    var duplicateNodeIds: Set<String> = []
    let onSelect: (NodeInfo, String?) -> Void
    let onCancel: () -> Void

    @State private var rootNodes: [NodeInfo] = []
    @State private var childrenByNodeId: [String: [NodeInfo]] = [:]
    @State private var expandedNodeIds = Set<String>()
    @State private var loadingNodeIds = Set<String>()
    @State private var selectedNode: NodeInfo?
    @State private var searchText = ""
    @State private var isLoadingRoot = false
    @State private var isValidating = false
    @State private var previewValue: String?
    @State private var errorMessage: String?
    @State private var validationMessage: String?

    private var selectableNodes: [NodeInfo] {
        flatten(rootNodes).filter(isSelectable)
    }

    private var filteredNodes: [NodeInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return selectableNodes }
        return selectableNodes.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            $0.nodeId.localizedCaseInsensitiveContains(query) ||
            ($0.dataType?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var selectedNodeIsDuplicate: Bool {
        guard let selectedNode else { return false }
        return duplicateNodeIds.contains(selectedNode.nodeId)
    }

    private var canConfirmSelection: Bool {
        guard selectedNode != nil, !selectedNodeIsDuplicate, !isValidating else { return false }
        if requiresReadableValue || requiresNumericValue {
            return previewValue != nil
        }
        return true
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                browserPane
                    .frame(minWidth: 420, idealWidth: 520)

                Divider()

                selectionPane
                    .frame(minWidth: 300, idealWidth: 360)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { onCancel() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) {
                        if let selectedNode {
                            onSelect(selectedNode, previewValue)
                        }
                    }
                    .disabled(!canConfirmSelection)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 820, minHeight: 620)
        #endif
        .onAppear(perform: loadRootNodes)
    }

    private var browserPane: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                Text(server.name)
                    .font(DesignSystem.Typography.headline)
                Text(instruction)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DesignSystem.Colors.tertiaryText)
                TextField("Search loaded variables...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(DesignSystem.Spacing.xSmall)
            .background(DesignSystem.Colors.tertiaryBackground)
            .cornerRadius(DesignSystem.CornerRadius.small)

            if isLoadingRoot {
                VStack(spacing: DesignSystem.Spacing.small) {
                    ProgressView()
                    Text("Loading address space...")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Address Space Unavailable",
                    systemImage: "network.slash",
                    description: Text(errorMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.xSmall) {
                        ForEach(filteredNodes) { node in
                            OPCUANodeValueSearchRow(
                                node: node,
                                isSelected: selectedNode?.nodeId == node.nodeId,
                                isDuplicate: duplicateNodeIds.contains(node.nodeId),
                                onSelect: { selectNode(node) }
                            )
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.xSmall)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                        ForEach(rootNodes.filter(isVisibleInPicker)) { node in
                            OPCUANodeValueTreeRow(
                                node: node,
                                level: 0,
                                selectedNodeId: selectedNode?.nodeId,
                                expandedNodeIds: expandedNodeIds,
                                loadingNodeIds: loadingNodeIds,
                                childrenByNodeId: childrenByNodeId,
                                duplicateNodeIds: duplicateNodeIds,
                                onToggle: toggleNode,
                                onSelect: selectNode
                            )
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.xSmall)
                }
            }
        }
        .padding()
        .background(DesignSystem.Colors.background)
    }

    private var selectionPane: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
            SectionHeader("SELECTION", icon: "tag")

            if let selectedNode {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    Text(selectedNode.displayName)
                        .font(DesignSystem.Typography.headline)
                    Text(selectedNode.nodeId)
                        .font(DesignSystem.Typography.monospacedCaption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

                    if let dataType = selectedNode.dataType {
                        Label(dataType, systemImage: "number")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }

                    if selectedNodeIsDuplicate {
                        Label("Already selected", systemImage: "checkmark.circle.fill")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.warning)
                    } else if isValidating {
                        Label("Checking current value...", systemImage: "hourglass")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    } else if let previewValue {
                        Label("Readable value: \(previewValue)", systemImage: "checkmark.circle.fill")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.success)
                    } else if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.error)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.tertiaryBackground)
                .cornerRadius(DesignSystem.CornerRadius.medium)
            } else {
                Text("Select a Variable node from the address space.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignSystem.Colors.tertiaryBackground)
                    .cornerRadius(DesignSystem.CornerRadius.medium)
            }

            Spacer()
        }
        .padding()
        .background(DesignSystem.Colors.tertiaryBackground)
    }

    private func loadRootNodes() {
        guard rootNodes.isEmpty, !isLoadingRoot else { return }
        guard appState.connectionManager.isConnected(to: server) else {
            errorMessage = "No OPC UA server is connected."
            return
        }

        isLoadingRoot = true
        errorMessage = nil

        Task {
            let nodes = await appState.connectionManager.browseAddressSpace(for: server, maxDepth: 1)
                .filter(isVisibleInPicker)

            await MainActor.run {
                rootNodes = nodes
                isLoadingRoot = false
                if nodes.isEmpty {
                    errorMessage = "The server returned no browsable nodes."
                }
            }
        }
    }

    private func toggleNode(_ node: NodeInfo) {
        guard isExpandable(node) else {
            selectNode(node)
            return
        }

        if expandedNodeIds.contains(node.nodeId) {
            expandedNodeIds.remove(node.nodeId)
            return
        }

        expandedNodeIds.insert(node.nodeId)

        guard childrenByNodeId[node.nodeId] == nil, !loadingNodeIds.contains(node.nodeId) else {
            return
        }

        loadingNodeIds.insert(node.nodeId)

        Task {
            let children = await appState.connectionManager.browseChildNodes(for: server, parentNodeId: node.nodeId)
                .filter(isVisibleInPicker)

            await MainActor.run {
                childrenByNodeId[node.nodeId] = children
                loadingNodeIds.remove(node.nodeId)
            }
        }
    }

    private func selectNode(_ node: NodeInfo) {
        guard isSelectable(node) else {
            validationMessage = "Only Variable nodes can be selected."
            return
        }

        selectedNode = node
        previewValue = nil
        validationMessage = nil
        errorMessage = nil

        guard !duplicateNodeIds.contains(node.nodeId) else {
            validationMessage = "This node is already selected."
            return
        }

        guard requiresReadableValue || requiresNumericValue else {
            return
        }

        isValidating = true

        Task {
            let value = await appState.connectionManager.readValue(for: server, nodeId: node.nodeId)

            await MainActor.run {
                guard selectedNode?.nodeId == node.nodeId else { return }
                isValidating = false

                guard let value, !value.isEmpty else {
                    validationMessage = "This Variable could not be read."
                    return
                }

                if requiresNumericValue && Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) == nil {
                    validationMessage = "Analytics requires a numeric value. Current value: \(value)"
                    return
                }

                previewValue = value
            }
        }
    }

    private func isVisibleInPicker(_ node: NodeInfo) -> Bool {
        isSelectable(node) || isExpandable(node)
    }

    private func isSelectable(_ node: NodeInfo) -> Bool {
        node.nodeClass == .variable
    }

    private func isExpandable(_ node: NodeInfo) -> Bool {
        node.nodeClass == .object || node.nodeClass == .view
    }

    private func flatten(_ nodes: [NodeInfo]) -> [NodeInfo] {
        nodes.flatMap { node in
            [node] + flatten(childrenByNodeId[node.nodeId] ?? node.children ?? [])
        }
    }
}

private struct OPCUANodeValueTreeRow: View {
    let node: NodeInfo
    let level: Int
    let selectedNodeId: String?
    let expandedNodeIds: Set<String>
    let loadingNodeIds: Set<String>
    let childrenByNodeId: [String: [NodeInfo]]
    let duplicateNodeIds: Set<String>
    let onToggle: (NodeInfo) -> Void
    let onSelect: (NodeInfo) -> Void

    private var isExpanded: Bool { expandedNodeIds.contains(node.nodeId) }
    private var isLoading: Bool { loadingNodeIds.contains(node.nodeId) }
    private var isSelectable: Bool { node.nodeClass == .variable }
    private var isExpandable: Bool { node.nodeClass == .object || node.nodeClass == .view }
    private var isSelected: Bool { selectedNodeId == node.nodeId }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
            Button(action: { isSelectable ? onSelect(node) : onToggle(node) }) {
                HStack(spacing: DesignSystem.Spacing.xSmall) {
                    if isExpandable {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 14)
                    } else {
                        Color.clear.frame(width: 14, height: 1)
                    }

                    Image(systemName: isSelectable ? "waveform.path.ecg" : "folder")
                        .foregroundColor(isSelectable ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.displayName)
                            .font(DesignSystem.Typography.callout)
                            .lineLimit(1)
                        Text(node.nodeId)
                            .font(DesignSystem.Typography.monospacedCaption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    if duplicateNodeIds.contains(node.nodeId) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(DesignSystem.Colors.warning)
                    } else if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else if isSelectable {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundColor(isSelected ? DesignSystem.Colors.success : DesignSystem.Colors.primary)
                    }
                }
                .padding(DesignSystem.Spacing.xSmall)
                .background(isSelected ? DesignSystem.Colors.primary.opacity(0.12) : Color.clear)
                .cornerRadius(DesignSystem.CornerRadius.small)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, CGFloat(level) * 18)

            if isExpanded {
                ForEach((childrenByNodeId[node.nodeId] ?? node.children ?? []).filter { child in
                    child.nodeClass == .variable || child.nodeClass == .object || child.nodeClass == .view
                }) { child in
                    OPCUANodeValueTreeRow(
                        node: child,
                        level: level + 1,
                        selectedNodeId: selectedNodeId,
                        expandedNodeIds: expandedNodeIds,
                        loadingNodeIds: loadingNodeIds,
                        childrenByNodeId: childrenByNodeId,
                        duplicateNodeIds: duplicateNodeIds,
                        onToggle: onToggle,
                        onSelect: onSelect
                    )
                }
            }
        }
    }
}

private struct OPCUANodeValueSearchRow: View {
    let node: NodeInfo
    let isSelected: Bool
    let isDuplicate: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignSystem.Spacing.small) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(DesignSystem.Colors.success)

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.displayName)
                        .font(DesignSystem.Typography.callout)
                    Text(node.nodeId)
                        .font(DesignSystem.Typography.monospacedCaption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }

                Spacer()

                if isDuplicate {
                    Text("Added")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(DesignSystem.Colors.warning)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.primary)
                }
            }
            .padding(DesignSystem.Spacing.small)
            .background(isSelected ? DesignSystem.Colors.primary.opacity(0.12) : DesignSystem.Colors.tertiaryBackground)
            .cornerRadius(DesignSystem.CornerRadius.small)
        }
        .buttonStyle(.plain)
    }
}
