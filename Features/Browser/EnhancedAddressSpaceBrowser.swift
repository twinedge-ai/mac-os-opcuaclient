import SwiftUI
import Combine

struct EnhancedAddressSpaceBrowser: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var browserViewModel = AddressSpaceBrowserViewModel()
    @State private var searchText = ""
    @State private var selectedView = ViewMode.tree
    @State private var selectedNodes = Set<NodeInfo>()
    @State private var showingNodeDetails = false
    @State private var detailNode: NodeInfo?
    @State private var showingBulkActions = false
    @State private var showingFilterOptions = false
    @State private var breadcrumbs: [NodeInfo] = []
    
    enum ViewMode: String, CaseIterable {
        case tree = "Tree"
        case graph = "Graph"
        case grid = "Grid"
        
        var icon: String {
            switch self {
            case .tree: return "list.bullet.indent"
            case .graph: return "network"
            case .grid: return "square.grid.3x3"
            }
        }
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                searchAndFilterBar
                
                if !breadcrumbs.isEmpty {
                    breadcrumbBar
                }
                
                if browserViewModel.isLoading {
                    loadingView
                } else if browserViewModel.filteredNodes.isEmpty {
                    emptyStateView
                } else {
                    contentView
                }
                
                if !selectedNodes.isEmpty {
                    bulkActionsBar
                }
            }
            
            if showingNodeDetails, let node = detailNode {
                nodeDetailOverlay(node: node)
            }
        }
        .navigationTitle("Address Space Browser")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                viewModeSelector
            }
        }
        .onAppear {
            browserViewModel.configure(appState: appState)
            if let server = appState.selectedServer {
                Task { @MainActor in
                    await browserViewModel.loadRootNodes(for: server)
                }
            }
        }
        .onChange(of: appState.selectedServer) { _, newValue in
            guard let server = newValue else {
                browserViewModel.resetToRoot()
                return
            }
            Task { @MainActor in
                await browserViewModel.loadRootNodes(for: server)
            }
        }
    }
    
    var searchAndFilterBar: some View {
        HStack(spacing: OPCTheme.Spacing.md) {
            SearchBar(text: $searchText, placeholder: "Search nodes...") {
                browserViewModel.search(searchText)
            }
            .onChange(of: searchText) { _, newValue in
                browserViewModel.liveSearch(newValue)
            }
            
            Button(action: { showingFilterOptions.toggle() }) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 20))
                    .foregroundColor(browserViewModel.activeFilters.isEmpty ? 
                                   OPCTheme.Colors.secondaryText : OPCTheme.Colors.primary)
            }
            .popover(isPresented: $showingFilterOptions) {
                FilterOptionsView(viewModel: browserViewModel)
            }
            
            if browserViewModel.searchHistory.count > 0 {
                Menu {
                    ForEach(browserViewModel.searchHistory, id: \.self) { term in
                        Button(term) {
                            searchText = term
                            browserViewModel.search(term)
                        }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18))
                        .foregroundColor(OPCTheme.Colors.secondaryText)
                }
            }
        }
        .padding()
        .background(OPCTheme.Colors.secondaryBackground)
    }
    
    var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPCTheme.Spacing.xs) {
                ForEach(Array(breadcrumbs.enumerated()), id: \.element.id) { index, node in
                    HStack(spacing: OPCTheme.Spacing.xs) {
                        Button(action: {
                            navigateToBreadcrumb(at: index)
                        }) {
                            Text(node.displayName)
                                .font(OPCTheme.Typography.caption1)
                                .foregroundColor(OPCTheme.Colors.primary)
                        }
                        
                        if index < breadcrumbs.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundColor(OPCTheme.Colors.tertiaryText)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, OPCTheme.Spacing.sm)
        }
        .background(OPCTheme.Colors.tertiaryBackground)
    }
    
    @ViewBuilder
    var contentView: some View {
        switch selectedView {
        case .tree:
            TreeView(
                nodes: browserViewModel.filteredNodes,
                selectedNodes: $selectedNodes,
                onNodeTap: { node in
                    if node.nodeClass == .object {
                        browserViewModel.expandNode(node)
                        breadcrumbs.append(node)
                    } else {
                        detailNode = node
                        showingNodeDetails = true
                    }
                },
                onNodeHover: { node in
                    browserViewModel.preloadNode(node)
                }
            )
        case .graph:
            GraphView(
                nodes: browserViewModel.filteredNodes,
                selectedNodes: $selectedNodes
            )
        case .grid:
            EnhancedGridView(
                nodes: browserViewModel.filteredNodes,
                selectedNodes: $selectedNodes
            )
        }
    }
    
    var viewModeSelector: some View {
        Menu {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button(action: { selectedView = mode }) {
                    Label(mode.rawValue, systemImage: mode.icon)
                }
            }
        } label: {
            Image(systemName: selectedView.icon)
                .font(.system(size: 18))
        }
    }
    
    var bulkActionsBar: some View {
        HStack {
            Text("\(selectedNodes.count) selected")
                .font(OPCTheme.Typography.caption1)
                .foregroundColor(OPCTheme.Colors.secondaryText)
            
            Spacer()
            
            HStack(spacing: OPCTheme.Spacing.md) {
                Button(action: { browserViewModel.subscribeToNodes(Array(selectedNodes)) }) {
                    Label("Subscribe", systemImage: "bell")
                }
                
                Button(action: { browserViewModel.copyNodePaths(Array(selectedNodes)) }) {
                    Label("Copy Paths", systemImage: "doc.on.doc")
                }
                
                Button(action: { browserViewModel.exportNodes(Array(selectedNodes)) }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                
                Button(action: { selectedNodes.removeAll() }) {
                    Label("Clear", systemImage: "xmark")
                }
            }
            .font(OPCTheme.Typography.caption1)
        }
        .padding()
        .background(OPCTheme.Colors.primary.opacity(0.1))
        .overlay(
            Rectangle()
                .fill(OPCTheme.Colors.primary)
                .frame(height: 2),
            alignment: .top
        )
    }
    
    var loadingView: some View {
        VStack(spacing: OPCTheme.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading address space...")
                .font(OPCTheme.Typography.callout)
                .foregroundColor(OPCTheme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var emptyStateView: some View {
        VStack(spacing: OPCTheme.Spacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(OPCTheme.Colors.tertiaryText)
            
            Text("No nodes found")
                .font(OPCTheme.Typography.title3)
                .foregroundColor(OPCTheme.Colors.text)
            
            Text("Try adjusting your search or reloading")
                .font(OPCTheme.Typography.body)
                .foregroundColor(OPCTheme.Colors.secondaryText)
                
            Button(action: { 
                if let server = appState.selectedServer {
                    Task { @MainActor in
                        browserViewModel.isLoading = true // Force loading state
                        await browserViewModel.loadRootNodes(for: server)
                    }
                }
            }) {
                Label("Reload Address Space", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    func nodeDetailOverlay(node: NodeInfo) -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    showingNodeDetails = false
                }
            
            EnhancedNodeDetailView(node: node, isPresented: $showingNodeDetails)
                .frame(maxWidth: 600)
                .padding()
        }
    }
    
    func navigateToBreadcrumb(at index: Int) {
        breadcrumbs = Array(breadcrumbs.prefix(index + 1))
        if let lastNode = breadcrumbs.last {
            browserViewModel.navigateToNode(lastNode)
        }
    }
}

struct TreeView: View {
    let nodes: [NodeInfo]
    @Binding var selectedNodes: Set<NodeInfo>
    let onNodeTap: (NodeInfo) -> Void
    let onNodeHover: (NodeInfo) -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(nodes) { node in
                    EnhancedNodeRow(
                        node: node,
                        isSelected: selectedNodes.contains(node),
                        onTap: { onNodeTap(node) },
                        onSelect: {
                            if selectedNodes.contains(node) {
                                selectedNodes.remove(node)
                            } else {
                                selectedNodes.insert(node)
                            }
                        }
                    )
                    .onHover { _ in onNodeHover(node) }
                }
            }
            .padding()
        }
    }
}

struct EnhancedNodeRow: View {
    let node: NodeInfo
    let isSelected: Bool
    let onTap: () -> Void
    let onSelect: () -> Void
    @State private var isHovered = false
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: OPCTheme.Spacing.md) {
                Button(action: onSelect) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? OPCTheme.Colors.primary : OPCTheme.Colors.secondaryText)
                        .font(.system(size: 18))
                }
                .buttonStyle(PlainButtonStyle())
                
                if node.children != nil {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(OPCTheme.Colors.secondaryText)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Spacer()
                        .frame(width: 20)
                }
                
                Image(systemName: node.nodeClass.systemImage)
                    .font(.system(size: 16))
                    .foregroundColor(node.nodeClass.color)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.displayName)
                        .font(OPCTheme.Typography.callout)
                        .foregroundColor(OPCTheme.Colors.text)
                    
                    HStack(spacing: OPCTheme.Spacing.sm) {
                        Text(node.nodeId)
                            .font(OPCTheme.Typography.caption2)
                            .foregroundColor(OPCTheme.Colors.tertiaryText)
                        
                        if let dataType = node.dataType {
                            Text("• \(dataType)")
                                .font(OPCTheme.Typography.caption2)
                                .foregroundColor(OPCTheme.Colors.tertiaryText)
                        }
                        
                        if let value = node.value {
                            Text("• \(value)")
                                .font(OPCTheme.Typography.caption2)
                                .foregroundColor(OPCTheme.Colors.success)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                if node.quality != .good {
                    QualityBadge(quality: node.quality)
                }
                
                Button(action: onTap) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 18))
                        .foregroundColor(OPCTheme.Colors.primary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, OPCTheme.Spacing.sm)
            .padding(.horizontal)
            .background(
                RoundedRectangle(cornerRadius: OPCTheme.Radius.sm)
                    .fill(isHovered ? OPCTheme.Colors.secondaryBackground : Color.clear)
            )
            .onHover { hovering in
                withAnimation(OPCTheme.Animation.fast) {
                    isHovered = hovering
                }
            }
            
            if isExpanded, let children = node.children {
                ForEach(children) { child in
                    EnhancedNodeRow(
                        node: child,
                        isSelected: false,
                        onTap: {},
                        onSelect: {}
                    )
                    .padding(.leading, 40)
                }
            }
        }
    }
}

struct GraphView: View {
    let nodes: [NodeInfo]
    @Binding var selectedNodes: Set<NodeInfo>
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(nodes) { node in
                    NodeGraphItem(
                        node: node,
                        isSelected: selectedNodes.contains(node),
                        position: randomPosition(in: geometry.size)
                    )
                }
            }
        }
        .background(
            DotPattern()
                .stroke(OPCTheme.Colors.tertiaryBackground, lineWidth: 1)
        )
    }
    
    func randomPosition(in size: CGSize) -> CGPoint {
        CGPoint(
            x: CGFloat.random(in: 50...(size.width - 50)),
            y: CGFloat.random(in: 50...(size.height - 50))
        )
    }
}

struct NodeGraphItem: View {
    let node: NodeInfo
    let isSelected: Bool
    let position: CGPoint
    
    var body: some View {
        VStack(spacing: OPCTheme.Spacing.xs) {
            ZStack {
                Circle()
                    .fill(node.nodeClass.color.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                Image(systemName: node.nodeClass.systemImage)
                    .font(.system(size: 24))
                    .foregroundColor(node.nodeClass.color)
            }
            
            Text(node.displayName)
                .font(OPCTheme.Typography.caption1)
                .foregroundColor(OPCTheme.Colors.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 80)
        }
        .position(position)
        .overlay(
            isSelected ?
            Circle()
                .stroke(OPCTheme.Colors.primary, lineWidth: 2)
                .frame(width: 70, height: 70)
                .position(position)
            : nil
        )
    }
}

struct EnhancedGridView: View {
    let nodes: [NodeInfo]
    @Binding var selectedNodes: Set<NodeInfo>
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150), spacing: OPCTheme.Spacing.md)
            ], spacing: OPCTheme.Spacing.md) {
                ForEach(nodes) { node in
                    NodeGridItem(
                        node: node,
                        isSelected: selectedNodes.contains(node),
                        onSelect: {
                            if selectedNodes.contains(node) {
                                selectedNodes.remove(node)
                            } else {
                                selectedNodes.insert(node)
                            }
                        }
                    )
                }
            }
            .padding()
        }
    }
}

struct NodeGridItem: View {
    let node: NodeInfo
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: OPCTheme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                        .fill(node.nodeClass.color.opacity(0.1))
                        .frame(height: 80)
                    
                    Image(systemName: node.nodeClass.systemImage)
                        .font(.system(size: 32))
                        .foregroundColor(node.nodeClass.color)
                }
                
                VStack(spacing: OPCTheme.Spacing.xs) {
                    Text(node.displayName)
                        .font(OPCTheme.Typography.callout)
                        .foregroundColor(OPCTheme.Colors.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    
                    Text(node.nodeClass.rawValue)
                        .font(OPCTheme.Typography.caption2)
                        .foregroundColor(OPCTheme.Colors.secondaryText)
                }
                .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(OPCTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: OPCTheme.Radius.lg)
                    .fill(OPCTheme.Colors.secondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPCTheme.Radius.lg)
                            .stroke(isSelected ? OPCTheme.Colors.primary : Color.clear, lineWidth: 2)
                    )
            )
            .scaleEffect(isHovered ? 1.05 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(OPCTheme.Animation.fast) {
                isHovered = hovering
            }
        }
    }
}

struct FilterOptionsView: View {
    @ObservedObject var viewModel: AddressSpaceBrowserViewModel
    @State private var selectedNodeClasses = Set<NodeInfo.NodeClass>()
    @State private var selectedQuality = Set<NodeInfo.Quality>()
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPCTheme.Spacing.lg) {
            Text("Filter Options")
                .font(OPCTheme.Typography.title3)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: OPCTheme.Spacing.sm) {
                Text("Node Class")
                    .font(OPCTheme.Typography.subheadline)
                    .foregroundColor(OPCTheme.Colors.secondaryText)
                
                FlowLayout(spacing: OPCTheme.Spacing.sm) {
                    ForEach(NodeInfo.NodeClass.allCases, id: \.self) { nodeClass in
                        FilterChip(
                            title: nodeClass.rawValue,
                            icon: nodeClass.systemImage,
                            color: nodeClass.color,
                            isSelected: selectedNodeClasses.contains(nodeClass)
                        ) {
                            if selectedNodeClasses.contains(nodeClass) {
                                selectedNodeClasses.remove(nodeClass)
                            } else {
                                selectedNodeClasses.insert(nodeClass)
                            }
                            viewModel.filterByNodeClass(Array(selectedNodeClasses))
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: OPCTheme.Spacing.sm) {
                Text("Quality")
                    .font(OPCTheme.Typography.subheadline)
                    .foregroundColor(OPCTheme.Colors.secondaryText)
                
                HStack(spacing: OPCTheme.Spacing.sm) {
                    ForEach([NodeInfo.Quality.good, .bad, .uncertain], id: \.self) { quality in
                        FilterChip(
                            title: quality.rawValue,
                            color: quality.color,
                            isSelected: selectedQuality.contains(quality)
                        ) {
                            if selectedQuality.contains(quality) {
                                selectedQuality.remove(quality)
                            } else {
                                selectedQuality.insert(quality)
                            }
                            viewModel.filterByQuality(Array(selectedQuality))
                        }
                    }
                }
            }
            
            HStack {
                Button("Clear All") {
                    selectedNodeClasses.removeAll()
                    selectedQuality.removeAll()
                    viewModel.clearFilters()
                }
                .foregroundColor(OPCTheme.Colors.error)
                
                Spacer()
                
                Button("Apply") {
                    viewModel.applyFilters()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

struct FilterChip: View {
    let title: String
    var icon: String? = nil
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: OPCTheme.Spacing.xs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }
                Text(title)
                    .font(OPCTheme.Typography.caption1)
            }
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, OPCTheme.Spacing.md)
            .padding(.vertical, OPCTheme.Spacing.xs)
            .background(
                Capsule()
                    .fill(isSelected ? color : color.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .stroke(color, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct QualityBadge: View {
    let quality: NodeInfo.Quality
    
    var body: some View {
        Text(quality.rawValue)
            .font(OPCTheme.Typography.caption2)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, OPCTheme.Spacing.sm)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(quality.color)
            )
    }
}

struct EnhancedNodeDetailView: View {
    let node: NodeInfo
    @Binding var isPresented: Bool
    @State private var currentValue = ""
    @State private var showWriteConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPCTheme.Spacing.lg) {
            HStack {
                Image(systemName: node.nodeClass.systemImage)
                    .font(.system(size: 24))
                    .foregroundColor(node.nodeClass.color)
                
                VStack(alignment: .leading) {
                    Text(node.displayName)
                        .font(OPCTheme.Typography.title2)
                        .fontWeight(.semibold)
                    
                    Text(node.nodeId)
                        .font(OPCTheme.Typography.caption1)
                        .foregroundColor(OPCTheme.Colors.secondaryText)
                }
                
                Spacer()
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(OPCTheme.Colors.secondaryText)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Divider()
            
            Grid(alignment: .leading, horizontalSpacing: OPCTheme.Spacing.xl, verticalSpacing: OPCTheme.Spacing.md) {
                GridRow {
                    Text("Node Class:")
                        .foregroundColor(OPCTheme.Colors.secondaryText)
                    Text(node.nodeClass.rawValue)
                        .fontWeight(.medium)
                }
                
                if let dataType = node.dataType {
                    GridRow {
                        Text("Data Type:")
                            .foregroundColor(OPCTheme.Colors.secondaryText)
                        Text(dataType)
                            .fontWeight(.medium)
                    }
                }
                
                GridRow {
                    Text("Quality:")
                        .foregroundColor(OPCTheme.Colors.secondaryText)
                    QualityBadge(quality: node.quality)
                }
                
                if let value = node.value {
                    GridRow {
                        Text("Current Value:")
                            .foregroundColor(OPCTheme.Colors.secondaryText)
                        Text(value)
                            .fontWeight(.medium)
                            .foregroundColor(OPCTheme.Colors.success)
                    }
                }
                
                if let timestamp = node.timestamp {
                    GridRow {
                        Text("Last Updated:")
                            .foregroundColor(OPCTheme.Colors.secondaryText)
                        Text(timestamp.formatted())
                            .fontWeight(.medium)
                    }
                }
            }
            .font(OPCTheme.Typography.callout)
            
            if node.nodeClass == .variable {
                Divider()
                
                VStack(alignment: .leading, spacing: OPCTheme.Spacing.sm) {
                    Text("Write Value")
                        .font(OPCTheme.Typography.headline)
                    
                    HStack {
                        TextField("Enter new value", text: $currentValue)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("Write") {
                            showWriteConfirmation = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(currentValue.isEmpty)
                    }
                }
            }
            
            HStack(spacing: OPCTheme.Spacing.md) {
                ModernButton(title: "Subscribe", icon: "bell", style: .primary) {
                    // Subscribe action
                }
                
                ModernButton(title: "Copy Path", icon: "doc.on.doc", style: .secondary) {
                    // Copy path action
                }
                
                Spacer()
            }
        }
        .padding(OPCTheme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: OPCTheme.Radius.xl)
                .fill(.regularMaterial)
        )
        .alert("Confirm Write", isPresented: $showWriteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Write", role: .destructive) {
                // Perform write operation
            }
        } message: {
            Text("Are you sure you want to write '\(currentValue)' to this node?")
        }
    }
}

struct FlowLayout: Layout {
    let spacing: CGFloat
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return CGSize(width: proposal.replacingUnspecifiedDimensions().width, height: result.height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        let positions: [CGPoint]
        let height: CGFloat
        
        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var positions: [CGPoint] = []
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > width && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            
            self.positions = positions
            self.height = currentY + lineHeight
        }
    }
}

struct DotPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 20
        
        for x in stride(from: 0, to: rect.width, by: spacing) {
            for y in stride(from: 0, to: rect.height, by: spacing) {
                path.addEllipse(in: CGRect(x: x, y: y, width: 2, height: 2))
            }
        }
        
        return path
    }
}

class AddressSpaceBrowserViewModel: ObservableObject {
    @Published var nodes: [NodeInfo] = []
    @Published var filteredNodes: [NodeInfo] = []
    @Published var isLoading = false
    @Published var searchHistory: [String] = []
    @Published var activeFilters: Set<String> = []
    @Published var favorites: [NodeInfo] = []
    
    private var nodeCache: [String: [NodeInfo]] = [:]
    private var allNodes: [NodeInfo] = []
    private var currentRootNodes: [NodeInfo] = []
    private var searchQuery: String = ""
    private var selectedNodeClasses: Set<NodeInfo.NodeClass> = []
    private var selectedQualities: Set<NodeInfo.Quality> = []
    private weak var appState: AppState?
    private weak var connectionManager: OPCUAConnectionManager?
    private var cancellables = Set<AnyCancellable>()
    
    func configure(appState: AppState) {
        self.appState = appState
        self.connectionManager = appState.connectionManager
        setupConnectionObserver()
        
        // Immediate check: If we are already connected when this view loads,
        // trigger the load process now.
        attemptAutoLoad()
    }
    
    private func setupConnectionObserver() {
        cancellables.removeAll()
        NotificationCenter.default.publisher(for: .opcuaConnectionChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.attemptAutoLoad()
            }
            .store(in: &cancellables)
    }
    
    private func attemptAutoLoad() {
        guard let server = appState?.selectedServer,
              let manager = connectionManager else { return }
        
        // If we are connected and have no nodes, try loading
        // We check !isLoading to avoid double-triggering
        if manager.isConnected(to: server) && nodes.isEmpty && !isLoading {
            Task { 
                await loadRootNodes(for: server) 
            }
        }
    }
    
    @MainActor
    func loadRootNodes(for server: OPCUAServer) async {
        guard let manager = connectionManager else { return }
        isLoading = true
        
        let status = manager.getConnectionStatus(for: server)
        guard status == .connected else {
            allNodes = []
            currentRootNodes = []
            nodes = []
            filteredNodes = []
            isLoading = false
            return
        }
        
        let loadedNodes = await manager.browseAddressSpace(for: server)
        allNodes = loadedNodes
        currentRootNodes = loadedNodes
        nodes = loadedNodes
        applyFilters()
        isLoading = false
    }
    
    func resetToRoot() {
        currentRootNodes = allNodes
        applyFilters()
    }
    
    func expandNode(_ node: NodeInfo) {
        if let children = node.children, !children.isEmpty {
            currentRootNodes = children
        } else {
            currentRootNodes = [node]
        }
        applyFilters()
    }
    
    func search(_ query: String) {
        searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchQuery.isEmpty else {
            applyFilters()
            return
        }
        
        if !searchHistory.contains(searchQuery) {
            searchHistory.insert(searchQuery, at: 0)
            if searchHistory.count > 10 {
                searchHistory.removeLast()
            }
        }
        
        applyFilters()
    }
    
    func liveSearch(_ query: String) {
        searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        applyFilters()
    }
    
    func filterByNodeClass(_ classes: [NodeInfo.NodeClass]) {
        selectedNodeClasses = Set(classes)
        applyFilters()
    }
    
    func filterByQuality(_ qualities: [NodeInfo.Quality]) {
        selectedQualities = Set(qualities)
        applyFilters()
    }
    
    func clearFilters() {
        selectedNodeClasses.removeAll()
        selectedQualities.removeAll()
        activeFilters.removeAll()
        applyFilters()
    }
    
    func applyFilters() {
        activeFilters.removeAll()
        if !searchQuery.isEmpty { activeFilters.insert("Search") }
        if !selectedNodeClasses.isEmpty { activeFilters.insert("NodeClass") }
        if !selectedQualities.isEmpty { activeFilters.insert("Quality") }
        
        filteredNodes = filterNodes(currentRootNodes)
    }
    
    func preloadNode(_ node: NodeInfo) {
        // Preload node data for performance
    }
    
    func navigateToNode(_ node: NodeInfo) {
        if let children = node.children, !children.isEmpty {
            currentRootNodes = children
        } else {
            currentRootNodes = [node]
        }
        applyFilters()
    }
    
    func subscribeToNodes(_ nodes: [NodeInfo]) {
        guard let appState = appState,
              let selectedServer = appState.selectedServer else { return }
        
        let variableNodes = nodes.filter { $0.nodeClass == .variable }
        guard !variableNodes.isEmpty else { return }
        
        if let existingSubscription = appState.subscriptions.first(where: { $0.serverId == selectedServer.id }) {
            for node in variableNodes {
                let newItem = MonitoredItem(
                    nodeId: node.nodeId,
                    displayName: node.displayName,
                    samplingInterval: 1000.0,
                    queueSize: 10,
                    discardOldest: true,
                    currentValue: node.value,
                    timestamp: Date(),
                    quality: node.quality
                )
                appState.addMonitoredItem(newItem, to: existingSubscription.id)
                
                Task {
                    await appState.connectionManager.addMonitoredItem(
                        for: selectedServer,
                        nodeId: node.nodeId,
                        samplingInterval: 1000.0
                    )
                }
            }
        } else {
            let items = variableNodes.map { node in
                MonitoredItem(
                    nodeId: node.nodeId,
                    displayName: node.displayName,
                    samplingInterval: 1000.0,
                    queueSize: 10,
                    discardOldest: true,
                    currentValue: node.value,
                    timestamp: Date(),
                    quality: node.quality
                )
            }
            
            let newSubscription = Subscription(
                name: "Subscription for \(selectedServer.name)",
                serverId: selectedServer.id,
                publishingInterval: 1000.0,
                priority: 1,
                isActive: true,
                monitoredItems: items
            )
            
            appState.saveSubscription(newSubscription)
            
            Task {
                let created = await appState.connectionManager.createSubscription(
                    for: selectedServer,
                    publishingInterval: newSubscription.publishingInterval
                )
                
                if created {
                    for node in variableNodes {
                        _ = await appState.connectionManager.addMonitoredItem(
                            for: selectedServer,
                            nodeId: node.nodeId,
                            samplingInterval: 1000.0
                        )
                    }
                }
            }
        }
    }
    
    func copyNodePaths(_ nodes: [NodeInfo]) {
        let paths = nodes.map { $0.nodeId }.joined(separator: "\n")
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
        #endif
    }
    
    func exportNodes(_ nodes: [NodeInfo]) {
        // Export selected nodes
    }
    
    private func filterNodes(_ inputNodes: [NodeInfo]) -> [NodeInfo] {
        var result: [NodeInfo] = []
        
        for node in inputNodes {
            let matches = nodeMatches(node)
            let filteredChildren = node.children.map { filterNodes($0) }
            let hasMatchingChildren = filteredChildren?.isEmpty == false
            
            if matches || hasMatchingChildren {
                let updatedNode = node
                updatedNode.children = filteredChildren
                result.append(updatedNode)
            }
        }
        
        return result
    }
    
    private func nodeMatches(_ node: NodeInfo) -> Bool {
        if !searchQuery.isEmpty {
            let matchesSearch = node.displayName.localizedCaseInsensitiveContains(searchQuery) ||
                node.nodeId.localizedCaseInsensitiveContains(searchQuery)
            if !matchesSearch {
                return false
            }
        }
        
        if !selectedNodeClasses.isEmpty && !selectedNodeClasses.contains(node.nodeClass) {
            return false
        }
        
        if !selectedQualities.isEmpty && !selectedQualities.contains(node.quality) {
            return false
        }
        
        return true
    }
}
