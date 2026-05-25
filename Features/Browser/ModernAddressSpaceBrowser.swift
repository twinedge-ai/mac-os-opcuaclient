import SwiftUI
import Combine

struct ModernAddressSpaceBrowser: View {
    @EnvironmentObject var appState: AppState
    @State private var nodes: [NodeInfo] = []
    @State private var selectedNode: NodeInfo?
    @State private var searchText = ""
    @State private var expandedNodes = Set<UUID>()
    @State private var showNodeDetails = false
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var breadcrumb: [NodeInfo] = []
    @State private var viewMode: ViewMode = .tree
    @State private var nodeTypeFilter: NodeTypeFilter = .all
    @State private var showingFilters = false
    @State private var treeRevision = 0
    @State private var flatSearchResults: [NodeInfo] = []
    @State private var isFlatSearchLoading = false
    @State private var flatSearchError: String?
    @State private var flatSearchTask: Task<Void, Never>?

    init(selectedItemID: String? = nil) {
        let mode: ViewMode
        switch selectedItemID {
        case "search":
            mode = .flat
        default:
            mode = .tree
        }
        _viewMode = State(initialValue: mode)
        _showNodeDetails = State(initialValue: selectedItemID == "inspector")
    }
    
    enum ViewMode: String, CaseIterable {
        case tree = "Tree"
        case flat = "Flat"
        case grid = "Grid"
        
        var icon: String {
            switch self {
            case .tree: return "list.bullet.indent"
            case .flat: return "list.bullet"
            case .grid: return "square.grid.2x2"
            }
        }
    }
    
    enum NodeTypeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case objects = "Objects"
        case variables = "Variables"
        case methods = "Methods"
        case objectTypes = "Object Types"
        case variableTypes = "Variable Types"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .all: return "circle.grid.cross"
            case .objects: return "folder"
            case .variables: return "doc.text"
            case .methods: return "bolt"
            case .objectTypes: return "folder.badge.gearshape"
            case .variableTypes: return "doc.badge.gearshape"
            }
        }
    }
    
    var filteredNodes: [NodeInfo] {
        var result = nodes
        
        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { node in
                node.displayName.localizedCaseInsensitiveContains(searchText) ||
                node.nodeId.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply node type filter
        if nodeTypeFilter != .all {
            result = result.filter { node in
                switch nodeTypeFilter {
                case .all:
                    return true
                case .objects:
                    return node.nodeClass == .object
                case .variables:
                    return node.nodeClass == .variable
                case .methods:
                    return node.nodeClass == .method
                case .objectTypes:
                    return node.nodeClass == .objectType
                case .variableTypes:
                    return node.nodeClass == .variableType
                }
            }
        }
        
        return result
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.tertiaryBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Server Selection and Controls
                    topControlsSection
                        .padding()
                        .background(DesignSystem.Colors.background)
                    
                    Divider()
                    
                    // Main Content
                    if activeServer == nil {
                        serverSelectionPrompt
                    } else if isLoading {
                        loadingView
                    } else if nodes.isEmpty {
                        emptyStateView
                    } else {
                        contentView
                    }
                }
            }
            .navigationTitle("Address Space Browser")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: { showingFilters.toggle() }) {
                        Image(systemName: showingFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    
                    Button(action: refreshNodes) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showNodeDetails) {
                if let node = selectedNode {
                    ModernNodeDetailsView(node: node)
                }
            }
            .sheet(isPresented: $showingFilters) {
                AddressSpaceFiltersView(
                    nodeTypeFilter: $nodeTypeFilter,
                    viewMode: $viewMode
                )
            }
        }
        .onAppear {
            loadAddressSpace()
        }
        .onChange(of: appState.selectedServer) { _, _ in
            loadAddressSpace()
        }
        .onChange(of: searchText) { _, _ in
            scheduleFlatSearchIfNeeded()
        }
        .onChange(of: viewMode) { _, _ in
            scheduleFlatSearchIfNeeded()
        }
    }
    
    // MARK: - Top Controls Section
    
    var topControlsSection: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            // Server Selection
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                    Text("SELECTED SERVER")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(DesignSystem.Colors.tertiaryText)
                    
                    if let server = activeServer {
                        HStack(spacing: DesignSystem.Spacing.xSmall) {
                            Circle()
                                .fill(appState.connectionManager.isConnected(to: server) ? DesignSystem.Colors.success : DesignSystem.Colors.error)
                                .frame(width: 8, height: 8)
                            
                            Text(server.name)
                                .font(DesignSystem.Typography.callout.weight(.medium))
                            
                            Text("(\(server.host))")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                        }
                    } else {
                        Text("No server selected")
                            .font(DesignSystem.Typography.callout)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                }
                
                Spacer()
                
                Button(action: loadAddressSpace) {
                    Label("Load", systemImage: "arrow.clockwise")
                        .font(DesignSystem.Typography.caption)
                }
                .buttonStyle(.bordered)
                .disabled(activeServer == nil || isLoading)
            }
            
            // Search and Filter
            HStack(spacing: DesignSystem.Spacing.small) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DesignSystem.Colors.tertiaryText)
                        .font(.system(size: 14))
                    
                    TextField("Search nodes, IDs, browse names...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(DesignSystem.Spacing.xSmall)
                .background(DesignSystem.Colors.tertiaryBackground)
                .cornerRadius(DesignSystem.CornerRadius.small)
                
                // Node Type Filter
                Menu {
                    ForEach(NodeTypeFilter.allCases) { filter in
                        Button(action: { nodeTypeFilter = filter }) {
                            Label(filter.rawValue, systemImage: filter.icon)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: nodeTypeFilter.icon)
                        Text(nodeTypeFilter.rawValue)
                    }
                    .font(DesignSystem.Typography.caption)
                    .padding(.horizontal, DesignSystem.Spacing.small)
                    .padding(.vertical, DesignSystem.Spacing.xSmall)
                    .background(nodeTypeFilter != .all ? DesignSystem.Colors.primary.opacity(0.1) : DesignSystem.Colors.tertiaryBackground)
                    .cornerRadius(DesignSystem.CornerRadius.small)
                }
                
                // View Mode
                Picker("View Mode", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
        }
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    var contentView: some View {
        switch viewMode {
        case .tree:
            treeView
        case .flat:
            flatView
        case .grid:
            gridView
        }
    }
    
    // MARK: - Tree View
    
    var treeView: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Breadcrumb
                if !breadcrumb.isEmpty {
                    breadcrumbView
                        .padding(DesignSystem.Spacing.small)
                        .background(DesignSystem.Colors.tertiaryBackground)
                    
                    Divider()
                }
                
                // Content
                #if os(macOS)
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.xxSmall) {
                ForEach(visibleTreeRows) { row in
                            ModernTreeNodeRow(
                                node: row.node,
                                isSelected: selectedNode?.id == row.node.id,
                                isExpanded: expandedNodes.contains(row.node.id),
                                level: row.level,
                                onSelect: {
                                    selectedNode = row.node
                                    addToBreadcrumb(row.node)
                                },
                                onToggleExpansion: { toggleNodeExpansion(row.node) }
                            )
                }
            }
            .padding(DesignSystem.Spacing.small)
        }
        .id(treeRevision)
                #else
                List {
                    ForEach(visibleTreeRows) { row in
                        ModernTreeNodeRow(
                            node: row.node,
                            isSelected: selectedNode?.id == row.node.id,
                            isExpanded: expandedNodes.contains(row.node.id),
                            level: row.level,
                            onSelect: {
                                selectedNode = row.node
                                addToBreadcrumb(row.node)
                            },
                            onToggleExpansion: { toggleNodeExpansion(row.node) }
                        )
                    }
                }
                #endif
            }
            .navigationTitle("Nodes")
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 500)
            #endif
        } detail: {
            if let node = selectedNode {
                ModernNodeDetailPanel(node: node)
            } else {
                nodeSelectionPrompt
            }
        }
    }
    
    // MARK: - Flat View
    
    var flatView: some View {
        NavigationSplitView {
            // Flat List Panel
            VStack(spacing: 0) {
                // Stats
                HStack {
                    Text("\(flatDisplayNodes.count) nodes")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                    
                    Spacer()

                    if isFlatSearchLoading {
                        HStack(spacing: DesignSystem.Spacing.xxSmall) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Searching full hierarchy")
                        }
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                    } else if let flatSearchError {
                        Text(flatSearchError)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.error)
                            .lineLimit(1)
                    }
                }
                .padding(DesignSystem.Spacing.small)
                .background(DesignSystem.Colors.tertiaryBackground)
                
                Divider()
                
                // List
                List(flatDisplayNodes, selection: $selectedNode) { node in
                    ModernFlatNodeRow(node: node)
                        .tag(node)
                }
                .listStyle(.plain)
            }
            .navigationTitle("Nodes")
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 500)
            #endif
        } detail: {
            if let node = selectedNode {
                ModernNodeDetailPanel(node: node)
            } else {
                nodeSelectionPrompt
            }
        }
    }
    
    // MARK: - Grid View
    
    var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 250, maximum: 300), spacing: DesignSystem.Spacing.medium)
            ], spacing: DesignSystem.Spacing.medium) {
                ForEach(filteredNodes) { node in
                    ModernNodeCard(
                        node: node,
                        isSelected: selectedNode?.id == node.id,
                        onSelect: { selectedNode = node }
                    )
                }
            }
            .padding()
        }
        .background(DesignSystem.Colors.background)
    }
    
    // MARK: - Empty States and Prompts
    
    var serverSelectionPrompt: some View {
        DesignSystemEmptyStateView(
            icon: "server.rack",
            title: "No Server Selected",
            message: "Select a connected server to browse its address space",
            action: {
                appState.selectedTab = .servers
            },
            actionLabel: "Go to Servers"
        )
    }
    
    var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
            
            Text("Loading Address Space...")
                .font(DesignSystem.Typography.headline)
            
            Text("This may take a moment for large address spaces")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var emptyStateView: some View {
        DesignSystemEmptyStateView(
            icon: "folder.badge.questionmark",
            title: "No Nodes Found",
            message: loadError ?? "The address space appears to be empty or unavailable",
            action: loadAddressSpace,
            actionLabel: "Retry"
        )
    }
    
    var nodeSelectionPrompt: some View {
        DesignSystemEmptyStateView(
            icon: "doc.text.magnifyingglass",
            title: "Select a Node",
            message: "Choose a node from the address space to view its properties and attributes"
        )
    }
    
    // MARK: - Breadcrumb View
    
    var breadcrumbView: some View {
        HStack {
            Text("Path:")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.xxSmall) {
                    ForEach(breadcrumb) { node in
                        HStack(spacing: DesignSystem.Spacing.xxSmall) {
                            Button(node.displayName) {
                                navigateToNode(node)
                            }
                            .font(DesignSystem.Typography.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(DesignSystem.Colors.primary)
                            
                            if node.id != breadcrumb.last?.id {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(DesignSystem.Colors.tertiaryText)
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            Button("Clear") {
                breadcrumb.removeAll()
            }
            .font(DesignSystem.Typography.caption2)
            .buttonStyle(.plain)
            .foregroundColor(DesignSystem.Colors.secondaryText)
        }
    }
    
    // MARK: - Helper Methods

    private var visibleTreeRows: [VisibleTreeRow] {
        visibleRows(from: filteredNodes, level: 0)
    }

    private var flatDisplayNodes: [NodeInfo] {
        let sourceNodes = isDeepFlatSearchActive ? flatSearchResults : flattenedLoadedNodes
        return sourceNodes.filter { node in
            matchesNodeTypeFilter(node)
        }
    }

    private var flattenedLoadedNodes: [NodeInfo] {
        flatten(nodes)
    }

    private var isDeepFlatSearchActive: Bool {
        viewMode == .flat && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func flatten(_ sourceNodes: [NodeInfo]) -> [NodeInfo] {
        var result: [NodeInfo] = []

        for node in sourceNodes {
            result.append(node)

            if let children = node.children, !children.isEmpty {
                result.append(contentsOf: flatten(children))
            }
        }

        return result
    }

    private func visibleRows(from sourceNodes: [NodeInfo], level: Int) -> [VisibleTreeRow] {
        var rows: [VisibleTreeRow] = []

        for node in sourceNodes {
            rows.append(VisibleTreeRow(node: node, level: level))

            if expandedNodes.contains(node.id), let children = node.children, !children.isEmpty {
                rows.append(contentsOf: visibleRows(from: filteredChildren(children), level: level + 1))
            }
        }

        return rows
    }

    private func filteredChildren(_ childNodes: [NodeInfo]) -> [NodeInfo] {
        childNodes.filter { node in
            let matchesSearch = searchText.isEmpty ||
                node.displayName.localizedCaseInsensitiveContains(searchText) ||
                node.nodeId.localizedCaseInsensitiveContains(searchText)

            return matchesSearch && matchesNodeTypeFilter(node)
        }
    }

    private func matchesNodeTypeFilter(_ node: NodeInfo) -> Bool {
        switch nodeTypeFilter {
        case .all:
            return true
        case .objects:
            return node.nodeClass == .object
        case .variables:
            return node.nodeClass == .variable
        case .methods:
            return node.nodeClass == .method
        case .objectTypes:
            return node.nodeClass == .objectType
        case .variableTypes:
            return node.nodeClass == .variableType
        }
    }

    private func matchesSearch(_ node: NodeInfo, query: String) -> Bool {
        node.displayName.localizedCaseInsensitiveContains(query) ||
        node.nodeId.localizedCaseInsensitiveContains(query)
    }

    private var activeServer: OPCUAServer? {
        if let selected = appState.selectedServer, appState.connectionManager.isConnected(to: selected) {
            return selected
        }
        return appState.servers.first { appState.connectionManager.isConnected(to: $0) }
    }
    
    private func loadAddressSpace() {
        guard let server = activeServer else { return }
        guard !isLoading else { return }
        
        isLoading = true
        loadError = nil
        
        Task {
            let rootNodes = await appState.connectionManager.browseAddressSpace(for: server)
            await MainActor.run {
                self.nodes = rootNodes
                self.selectedNode = rootNodes.first
                self.treeRevision += 1
                self.isLoading = false
                self.scheduleFlatSearchIfNeeded()
            }
        }
    }
    
    private func refreshNodes() {
        nodes.removeAll()
        selectedNode = nil
        breadcrumb.removeAll()
        expandedNodes.removeAll()
        flatSearchTask?.cancel()
        flatSearchResults.removeAll()
        isFlatSearchLoading = false
        flatSearchError = nil
        treeRevision += 1
        loadAddressSpace()
    }
    
    private func toggleNodeExpansion(_ node: NodeInfo) {
        guard !node.isLoading else { return }

        selectedNode = node
        addToBreadcrumb(node)

        if expandedNodes.contains(node.id) {
            expandedNodes.remove(node.id)
            node.isExpanded = false
        } else if let children = node.children, !children.isEmpty {
            expandedNodes.insert(node.id)
            node.isExpanded = true
        } else {
            expandedNodes.insert(node.id)
            node.isExpanded = true
            treeRevision += 1
            loadChildNodes(for: node)
        }
    }
    
    private func loadChildNodes(for parent: NodeInfo) {
        guard !parent.isLoading else { return }

        guard parent.hasChildren else {
            expandedNodes.remove(parent.id)
            parent.isExpanded = false
            return
        }

        if let children = parent.children, !children.isEmpty {
            return
        }

        guard let server = activeServer else {
            loadError = "Connect to an OPC UA server before browsing child nodes."
            return
        }

        parent.isLoading = true

        Task {
            await Task.yield()
            let children = await appState.connectionManager.browseChildNodes(for: server, parentNodeId: parent.nodeId)
            await MainActor.run {
                parent.children = children
                parent.hasChildren = !children.isEmpty
                parent.isLoading = false
                treeRevision += 1

                if children.isEmpty {
                    expandedNodes.remove(parent.id)
                    parent.isExpanded = false
                } else {
                    expandedNodes.insert(parent.id)
                    parent.isExpanded = true
                    if selectedNode?.id == parent.id {
                        selectedNode = parent
                    }
                }
            }
        }
    }

    private func scheduleFlatSearchIfNeeded() {
        flatSearchTask?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard viewMode == .flat, !query.isEmpty else {
            flatSearchResults.removeAll()
            isFlatSearchLoading = false
            flatSearchError = nil
            return
        }

        guard let server = activeServer else {
            flatSearchResults.removeAll()
            isFlatSearchLoading = false
            flatSearchError = "Connect to search"
            return
        }

        guard !nodes.isEmpty else {
            flatSearchResults.removeAll()
            isFlatSearchLoading = false
            flatSearchError = nil
            return
        }

        isFlatSearchLoading = true
        flatSearchError = nil

        flatSearchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            let results = await searchFullAddressSpace(server: server, query: query)

            await MainActor.run {
                guard !Task.isCancelled,
                      self.viewMode == .flat,
                      self.searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query
                else { return }

                self.flatSearchResults = results
                self.isFlatSearchLoading = false
                self.flatSearchError = results.isEmpty ? "No matches" : nil
                if let selectedNode, !results.contains(where: { $0.id == selectedNode.id }) {
                    self.selectedNode = results.first
                } else if selectedNode == nil {
                    self.selectedNode = results.first
                }
            }
        }
    }

    @MainActor
    private func searchFullAddressSpace(server: OPCUAServer, query: String) async -> [NodeInfo] {
        let maxNodesToInspect = 5_000
        let maxMatches = 500
        var visitedNodeIds = Set<String>()
        var pendingNodes = nodes
        var matches: [NodeInfo] = []
        var inspectedCount = 0

        while !pendingNodes.isEmpty,
              inspectedCount < maxNodesToInspect,
              matches.count < maxMatches,
              !Task.isCancelled {
            let node = pendingNodes.removeFirst()

            guard visitedNodeIds.insert(node.nodeId).inserted else {
                continue
            }

            inspectedCount += 1

            if matchesSearch(node, query: query) {
                matches.append(node)
            }

            if let children = node.children {
                pendingNodes.append(contentsOf: children)
            } else if node.hasChildren {
                node.isLoading = true
                let children = await appState.connectionManager.browseChildNodes(for: server, parentNodeId: node.nodeId)
                node.children = children
                node.hasChildren = !children.isEmpty
                node.isLoading = false
                pendingNodes.append(contentsOf: children)
                treeRevision += 1
            }

            if inspectedCount.isMultiple(of: 25) {
                await Task.yield()
            }
        }

        return matches
    }
    
    private func addToBreadcrumb(_ node: NodeInfo) {
        if !breadcrumb.contains(where: { $0.id == node.id }) {
            breadcrumb.append(node)
        }
    }
    
    private func navigateToNode(_ node: NodeInfo) {
        selectedNode = node
        if let index = breadcrumb.firstIndex(where: { $0.id == node.id }) {
            breadcrumb.removeSubrange((index + 1)...)
        }
    }
}

// MARK: - Node Row Components

private struct VisibleTreeRow: Identifiable {
    let node: NodeInfo
    let level: Int

    var id: UUID { node.id }
}

struct ModernTreeNodeRow: View {
    @ObservedObject var node: NodeInfo
    let isSelected: Bool
    let isExpanded: Bool
    let level: Int
    let onSelect: () -> Void
    let onToggleExpansion: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xSmall) {
            // Indentation
            Rectangle()
                .fill(Color.clear)
                .frame(width: CGFloat(level) * 20)
            
            // Expansion Button
            if node.hasChildren || (node.children != nil && !node.children!.isEmpty) {
                Button(action: onToggleExpansion) {
                    if node.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .disabled(node.isLoading)
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 16)
            }
            
            // Node Icon
            nodeIcon
            
            // Node Info
            VStack(alignment: .leading, spacing: 2) {
                Text(node.displayName)
                    .font(DesignSystem.Typography.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                
                Text(node.nodeId)
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.tertiaryText)
                    .lineLimit(1)
            }
            
            Spacer()

            if node.isLoading {
                HStack(spacing: DesignSystem.Spacing.xxSmall) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading children")
                        .font(DesignSystem.Typography.caption2)
                }
                .foregroundColor(DesignSystem.Colors.secondaryText)
            }
            
            // Node Type Badge
            NodeTypeBadge(nodeClass: node.nodeClass)
        }
        .padding(DesignSystem.Spacing.xSmall)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                .fill(isSelected ? DesignSystem.Colors.primary.opacity(0.1) : 
                      isHovered ? DesignSystem.Colors.tertiaryBackground : Color.clear)
        )
        .onTapGesture {
            onSelect()
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Expand All Children", action: onToggleExpansion)
            Button("Add to Monitoring", action: {})
            Divider()
            Button("Copy Node ID", action: {})
        }
    }
    
    var nodeIcon: some View {
        Image(systemName: node.nodeClass == .object ? "folder" : 
              node.nodeClass == .variable ? "doc.text" :
              node.nodeClass == .method ? "bolt" : "circle")
            .font(.system(size: 16))
            .foregroundColor(nodeIconColor)
    }
    
    var nodeIconColor: Color {
        switch node.nodeClass {
        case .object: return DesignSystem.Colors.warning
        case .variable: return DesignSystem.Colors.success
        case .method: return DesignSystem.Colors.primary
        default: return DesignSystem.Colors.secondaryText
        }
    }
}

struct ModernFlatNodeRow: View {
    let node: NodeInfo
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            // Node Icon
            Image(systemName: node.nodeClass == .object ? "folder" : 
                  node.nodeClass == .variable ? "doc.text" :
                  node.nodeClass == .method ? "bolt" : "circle")
                .font(.system(size: 16))
                .foregroundColor(nodeIconColor)
                .frame(width: 20)
            
            // Node Info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                Text(node.displayName)
                    .font(DesignSystem.Typography.callout)
                    .lineLimit(1)
                
                Text(node.nodeId)
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.tertiaryText)
                    .lineLimit(1)
            }
            
            Spacer()
            
            NodeTypeBadge(nodeClass: node.nodeClass)
        }
        .padding(DesignSystem.Spacing.xSmall)
        .background(isHovered ? DesignSystem.Colors.tertiaryBackground : Color.clear)
        .cornerRadius(DesignSystem.CornerRadius.small)
        .onHover { isHovered = $0 }
    }
    
    var nodeIconColor: Color {
        switch node.nodeClass {
        case .object: return DesignSystem.Colors.warning
        case .variable: return DesignSystem.Colors.success
        case .method: return DesignSystem.Colors.primary
        default: return DesignSystem.Colors.secondaryText
        }
    }
}

struct ModernNodeCard: View {
    let node: NodeInfo
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack {
                Image(systemName: nodeIcon)
                    .font(.title2)
                    .foregroundColor(nodeIconColor)
                
                Spacer()
                
                NodeTypeBadge(nodeClass: node.nodeClass)
            }
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                Text(node.displayName)
                    .font(DesignSystem.Typography.callout.weight(.medium))
                    .lineLimit(2)
                
                Text(node.nodeId)
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.tertiaryText)
                    .lineLimit(1)
            }
            
            if let value = node.value {
                Text(value)
                    .font(DesignSystem.Typography.monospacedCaption)
                    .foregroundColor(DesignSystem.Colors.primary)
                    .lineLimit(1)
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    
    var nodeIcon: String {
        switch node.nodeClass {
        case .object: return "folder"
        case .variable: return "doc.text"
        case .method: return "bolt"
        default: return "circle"
        }
    }
    
    var nodeIconColor: Color {
        switch node.nodeClass {
        case .object: return DesignSystem.Colors.warning
        case .variable: return DesignSystem.Colors.success
        case .method: return DesignSystem.Colors.primary
        default: return DesignSystem.Colors.secondaryText
        }
    }
}

// MARK: - Supporting Components

struct NodeTypeBadge: View {
    let nodeClass: NodeInfo.NodeClass
    
    var body: some View {
        Text(nodeClass.rawValue)
            .font(DesignSystem.Typography.caption2)
            .foregroundColor(badgeColor)
            .padding(.horizontal, DesignSystem.Spacing.xxSmall)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .cornerRadius(DesignSystem.CornerRadius.small)
    }
    
    var badgeColor: Color {
        switch nodeClass {
        case .object: return DesignSystem.Colors.warning
        case .variable: return DesignSystem.Colors.success
        case .method: return DesignSystem.Colors.primary
        case .objectType: return DesignSystem.Colors.info
        case .variableType: return DesignSystem.Colors.secondaryText
        default: return DesignSystem.Colors.tertiaryText
        }
    }
}

struct ModernNodeDetailPanel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var node: NodeInfo
    @State private var selectedDetailTab = 0
    @State private var isReadingValue = false
    @State private var readError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                HStack {
                    Image(systemName: node.nodeClass == .object ? "folder" : 
                          node.nodeClass == .variable ? "doc.text" :
                          node.nodeClass == .method ? "bolt" : "circle")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.displayName)
                            .font(DesignSystem.Typography.headline)
                        
                        Text(node.nodeId)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                    
	                    Spacer()

	                    if node.nodeClass == .variable {
	                        Button(action: readCurrentValue) {
	                            if isReadingValue {
	                                ProgressView()
	                                    .controlSize(.small)
	                            } else {
	                                Label("Read Value", systemImage: "arrow.down.doc")
	                            }
	                        }
	                        .buttonStyle(.borderedProminent)
	                        .disabled(isReadingValue || activeServer == nil)
	                        .help(activeServer == nil ? "Connect to an OPC UA server to read this value" : "Read current value")
	                    }
	                    
	                    NodeTypeBadge(nodeClass: node.nodeClass)
	                }
                
                if let value = node.value {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                        Text("Current Value")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                        
                        Text(value)
                            .font(DesignSystem.Typography.title3)
                            .fontWeight(.semibold)
                    }
                }
            }
            .padding(DesignSystem.Spacing.medium)
            .background(DesignSystem.Colors.tertiaryBackground)
            
            // Tabs
            Picker("Details", selection: $selectedDetailTab) {
                Text("Properties").tag(0)
                Text("Attributes").tag(1)
                Text("References").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(DesignSystem.Spacing.medium)
            
            // Tab Content
            ScrollView {
                Group {
                    switch selectedDetailTab {
                    case 0:
                        nodePropertiesView
                    case 1:
                        nodeAttributesView
                    case 2:
                        nodeReferencesView
                    default:
                        EmptyView()
                    }
                }
                .padding(DesignSystem.Spacing.medium)
            }
        }
        .background(DesignSystem.Colors.background)
    }
    
    var nodePropertiesView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            PropertyRow(label: "Display Name", value: node.displayName)
            PropertyRow(label: "Node ID", value: node.nodeId)
            PropertyRow(label: "Browse Name", value: node.displayName)
            PropertyRow(label: "Node Class", value: node.nodeClass.rawValue)
            PropertyRow(label: "Description", value: node.dataType ?? "—")
            PropertyRow(label: "Data Type", value: node.dataType ?? "—")
            PropertyRow(label: "Access Level", value: "Read/Write")
            PropertyRow(label: "Has Children", value: node.hasChildren ? "Yes" : "No")
        }
    }
    
    var nodeAttributesView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            if let readError {
                Label(readError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(DesignSystem.Typography.caption)
                    .padding(.bottom, DesignSystem.Spacing.xxSmall)
            }
            PropertyRow(label: "Value", value: node.value ?? "—")
            PropertyRow(label: "Quality", value: node.quality.rawValue)
            PropertyRow(label: "Timestamp", value: node.timestamp?.formatted() ?? "—")
            PropertyRow(label: "User Access Level", value: "Read/Write")
            PropertyRow(label: "Write Mask", value: "0x00")
            PropertyRow(label: "User Write Mask", value: "0x00")
        }
    }
    
    var nodeReferencesView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text("References will be loaded here")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .padding()
        }
    }

    private var activeServer: OPCUAServer? {
        if let selected = appState.selectedServer, appState.connectionManager.isConnected(to: selected) {
            return selected
        }
        return appState.servers.first { appState.connectionManager.isConnected(to: $0) }
    }

    private func readCurrentValue() {
        guard let server = activeServer else {
            readError = "Connect to an OPC UA server before reading this node."
            return
        }

        isReadingValue = true
        readError = nil
        selectedDetailTab = 1

        Task {
            await Task.yield()
            let value = await appState.connectionManager.readNodeValue(for: server, nodeId: node.nodeId)
            await MainActor.run {
                isReadingValue = false
                node.timestamp = Date()

                if let value {
                    node.value = value
                    node.quality = .good
                } else {
                    node.quality = .bad
                    readError = "Read failed for \(node.nodeId)."
                }
            }
        }
    }
}

struct PropertyRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
            
            Text(value)
                .font(DesignSystem.Typography.callout)
                .textSelection(.enabled)
        }
        .padding(DesignSystem.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.tertiaryBackground.opacity(0.5))
        .cornerRadius(DesignSystem.CornerRadius.small)
    }
}

// MARK: - Filter Sheet

struct AddressSpaceFiltersView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var nodeTypeFilter: ModernAddressSpaceBrowser.NodeTypeFilter
    @Binding var viewMode: ModernAddressSpaceBrowser.ViewMode
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Node Types") {
                    Picker("Filter", selection: $nodeTypeFilter) {
                        ForEach(ModernAddressSpaceBrowser.NodeTypeFilter.allCases) { filter in
                            Label(filter.rawValue, systemImage: filter.icon)
                                .tag(filter)
                        }
                    }
                    .pickerStyle(.automatic)
                }
                
                Section("View Mode") {
                    Picker("Mode", selection: $viewMode) {
                        ForEach(ModernAddressSpaceBrowser.ViewMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.automatic)
                }
            }
            .navigationTitle("Filters & View")
            // .navigationBarTitleDisplayMode(.inline) // Not available on macOS
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

struct ModernNodeDetailsView: View {
    @Environment(\.dismiss) var dismiss
    let node: NodeInfo
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.large) {
                    ModernCard {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                            SectionHeader( "NODE INFORMATION", icon: "info.circle")
                            
                            PropertyRow(label: "Display Name", value: node.displayName)
                            PropertyRow(label: "Node ID", value: node.nodeId)
                            PropertyRow(label: "Browse Name", value: node.displayName)
                            PropertyRow(label: "Node Class", value: node.nodeClass.rawValue)
                        }
                    }
                    
                    if let value = node.value {
                        ModernCard {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                                SectionHeader( "CURRENT VALUE", icon: "doc.text")
                                
                                Text(value)
                                    .font(DesignSystem.Typography.title2)
                                    .fontWeight(.semibold)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    
                    ModernCard {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                            SectionHeader( "PROPERTIES", icon: "list.bullet")
                            
                            PropertyRow(label: "Data Type", value: node.dataType ?? "—")
                            PropertyRow(label: "Access Level", value: "Read/Write")
                            PropertyRow(label: "Description", value: node.dataType ?? "—")
                            PropertyRow(label: "Has Children", value: (node.children != nil && !node.children!.isEmpty) ? "Yes" : "No")
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Node Details")
            // .navigationBarTitleDisplayMode(.inline) // Not available on macOS
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }
}

#Preview {
    ModernAddressSpaceBrowser()
        .environmentObject(AppState())
}
