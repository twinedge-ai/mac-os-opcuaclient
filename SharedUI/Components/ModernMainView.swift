import SwiftUI

struct ModernMainView: View {
    @EnvironmentObject var appState: AppState
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var selectedWorkspaceItem: EnterpriseWorkspaceItem?
    @State private var searchText = ""
    @State private var isWorkspaceListCollapsed = false

    var body: some View {
        ZStack {
            #if os(iOS)
            mobileView
            #else
            desktopView
            #endif

            if appState.isConnecting {
                ModernConnectionOverlay(serverName: appState.connectingServerName)
            }
        }
        .sheet(isPresented: $appState.showingDatabaseManagement) {
            ModernDatabaseManagementView()
        }
        .sheet(isPresented: $appState.showingServerConnection) {
            ModernServerConfigurationView(server: nil)
        }
    }

    private var desktopView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            EnterpriseSidebar(searchText: $searchText)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } content: {
            if isWorkspaceListCollapsed {
                CollapsedWorkspaceRail(workspace: appState.selectedTab) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isWorkspaceListCollapsed = false
                    }
                }
                .navigationSplitViewColumnWidth(min: 44, ideal: 48, max: 56)
            } else {
                EnterpriseWorkspaceList(
                    workspace: appState.selectedTab,
                    selectedItem: $selectedWorkspaceItem,
                    searchText: searchText,
                    isCollapsed: $isWorkspaceListCollapsed
                )
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
            }
        } detail: {
            EnterpriseWorkspaceDetail(
                workspace: appState.selectedTab,
                selectedItem: selectedWorkspaceItem
            )
            .id("\(appState.selectedTab.id)-\(selectedWorkspaceItem?.id ?? "default")")
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            EnterpriseToolbar()
        }
    }

    private var mobileView: some View {
        TabView(selection: $appState.selectedTab) {
            ForEach(AppState.MainTab.allCases) { tab in
                NavigationStack {
                    EnterpriseWorkspaceDetail(workspace: tab, selectedItem: nil)
                }
                .tabItem {
                    Label(tab.rawValue, systemImage: tab.systemImage)
                }
                .tag(tab)
            }
        }
    }
}

struct EnterpriseSidebar: View {
    @EnvironmentObject var appState: AppState
    @Binding var searchText: String

    private var connectedCount: Int {
        appState.servers.filter { appState.connectionManager.isConnected(to: $0) }.count
    }

    var body: some View {
        List {
            Section {
                ForEach(AppState.MainTab.allCases) { workspace in
                    Button {
                        if appState.selectedTab != workspace {
                            appState.selectedTab = workspace
                        }
                    } label: {
                        Label(workspace.rawValue, systemImage: workspace.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(appState.selectedTab == workspace ? Color.primary.opacity(0.12) : Color.clear)
                }
            } header: {
                Text("Workspaces")
            }

            if !appState.servers.isEmpty {
                Section("Active Sessions") {
                    ForEach(appState.servers.filter { appState.connectionManager.isConnected(to: $0) }) { server in
                        EnterpriseServerSessionRow(server: server)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search servers, nodes, reports")
        .navigationTitle("OPC UA Client")
        .safeAreaInset(edge: .bottom) {
            EnterpriseSidebarFooter(connectedCount: connectedCount)
        }
    }
}

private struct EnterpriseSidebarFooter: View {
    @EnvironmentObject var appState: AppState
    let connectedCount: Int

    var body: some View {
        VStack(spacing: 8) {
            Divider()

            HStack {
                Label("\(connectedCount) connected", systemImage: connectedCount > 0 ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(connectedCount > 0 ? .green : .secondary)

                Spacer()

                Button {
                    appState.showingServerConnection = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .help("New Connection Profile")
                .accessibilityLabel("New Connection Profile")
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }
}

private struct EnterpriseServerSessionRow: View {
    @EnvironmentObject var appState: AppState
    let server: OPCUAServer

    var body: some View {
        let status = appState.connectionManager.getConnectionStatus(for: server)
        HStack(spacing: 8) {
            Image(systemName: status.systemImage)
                .foregroundStyle(status.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .lineLimit(1)
                Text(server.endpoint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct EnterpriseWorkspaceList: View {
    @EnvironmentObject var appState: AppState
    let workspace: AppState.MainTab
    @Binding var selectedItem: EnterpriseWorkspaceItem?
    let searchText: String
    @Binding var isCollapsed: Bool

    private var items: [EnterpriseWorkspaceItem] {
        EnterpriseWorkspaceItem.items(for: workspace, appState: appState)
            .filter { item in
                searchText.isEmpty ||
                item.title.localizedCaseInsensitiveContains(searchText) ||
                item.subtitle.localizedCaseInsensitiveContains(searchText)
            }
    }

    var body: some View {
        List {
            Section(workspace.rawValue) {
                ForEach(items) { item in
                    Button {
                        if selectedItem != item {
                            selectedItem = item
                        }
                    } label: {
                        EnterpriseWorkspaceItemRow(item: item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedItem == item ? Color.accentColor.opacity(0.16) : Color.clear)
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle(workspace.rawValue)
        .safeAreaInset(edge: .top) {
            HStack {
                Text(workspace.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isCollapsed = true
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .buttonStyle(.borderless)
                .help("Collapse Workspace Navigator")
                .accessibilityLabel("Collapse Workspace Navigator")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .onAppear {
            selectedItem = selectedItem ?? items.first
        }
        .onChange(of: workspace) { _, _ in
            selectedItem = items.first
        }
        .safeAreaInset(edge: .bottom) {
            EnterpriseWorkspaceListFooter(workspace: workspace, itemCount: items.count)
        }
    }
}

private struct CollapsedWorkspaceRail: View {
    let workspace: AppState.MainTab
    let expand: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: expand) {
                Image(systemName: "sidebar.trailing")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Show Workspace Navigator")
            .accessibilityLabel("Show Workspace Navigator")

            Text(workspace.rawValue)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(width: 28, height: 160)

            Spacer()
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.bar)
    }
}

private struct EnterpriseWorkspaceItemRow: View {
    let item: EnterpriseWorkspaceItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.systemImage)
                .foregroundStyle(item.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.callout)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct EnterpriseWorkspaceListFooter: View {
    let workspace: AppState.MainTab
    let itemCount: Int

    var body: some View {
        HStack {
            Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
            Spacer()
            Text(workspace.rawValue)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct EnterpriseWorkspaceDetail: View {
    @EnvironmentObject var appState: AppState
    let workspace: AppState.MainTab
    let selectedItem: EnterpriseWorkspaceItem?

    private var hasConnectedServer: Bool {
        appState.servers.contains { appState.connectionManager.isConnected(to: $0) }
    }

    var body: some View {
        NavigationStack {
            workspaceContent
                .navigationTitle(workspace.rawValue)
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch workspace {
        case .servers:
            ServerListView()
        case .browse:
            liveSessionRequired {
                ModernAddressSpaceBrowser(selectedItemID: selectedItem?.id)
            }
        case .readWrite:
            liveSessionRequired {
                ReadWriteWorkspaceView(selectedItemID: selectedItem?.id)
            }
        case .subscriptions:
            liveSessionRequired {
                ModernSubscriptionsView()
            }
        case .monitor:
            liveSessionRequired {
                ModernMonitoringDashboard(selectedItemID: selectedItem?.id)
            }
        case .analytics:
            liveSessionRequired {
                ModernAnalyticsView(selectedItemID: selectedItem?.id)
            }
        case .alarms:
            liveSessionRequired {
                AlarmEventManagementView(selectedItemID: selectedItem?.id)
            }
        case .history:
            liveSessionRequired {
                HistoryWorkspaceView(selectedItemID: selectedItem?.id)
            }
        case .diagnostics:
            DiagnosticsView(selectedItemID: selectedItem?.id)
        case .security:
            SecurityWorkspaceView(selectedItemID: selectedItem?.id)
        case .reports:
            ReportsWorkspaceView(selectedItemID: selectedItem?.id)
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private func liveSessionRequired<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if hasConnectedServer {
            content()
        } else {
            OPCUASessionRequiredView(workspace: workspace)
        }
    }
}

private struct EnterpriseToolbar: ToolbarContent {
    @EnvironmentObject var appState: AppState

    private var hasConnectedServer: Bool {
        appState.servers.contains { appState.connectionManager.isConnected(to: $0) }
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                appState.showingServerConnection = true
            } label: {
                Label("Connect", systemImage: "bolt.horizontal.circle")
            }
            .help("Connect to Server")

            Button {
                appState.connectionManager.disconnectAll()
            } label: {
                Label("Disconnect", systemImage: "xmark.circle")
            }
            .disabled(appState.servers.allSatisfy { !appState.connectionManager.isConnected(to: $0) })
            .help("Disconnect All Servers")

            Divider()

            Button {
                appState.selectedTab = .browse
            } label: {
                Label("Read", systemImage: "arrow.down.doc")
            }
            .disabled(!hasConnectedServer)
            .help("Read Selected Node")

            Button {
                appState.selectedTab = .readWrite
            } label: {
                Label("Write", systemImage: "square.and.pencil")
            }
            .disabled(!hasConnectedServer)
            .help("Write Selected Node")

            Button {
                appState.selectedTab = .subscriptions
            } label: {
                Label("Subscribe", systemImage: "bell.badge")
            }
            .disabled(!hasConnectedServer)
            .help("Create Subscription")

            Divider()

            Button {
                appState.selectedTab = .reports
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export Workspace Data")

            Button {
                appState.selectedTab = .diagnostics
            } label: {
                Label("Diagnostics", systemImage: "stethoscope")
            }
            .help("Open Diagnostics")
        }
    }
}

struct EnterpriseWorkspaceItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    static func items(for workspace: AppState.MainTab, appState: AppState) -> [EnterpriseWorkspaceItem] {
        switch workspace {
        case .servers:
            if appState.servers.isEmpty {
                return [EnterpriseWorkspaceItem(id: "new-profile", title: "New Connection Profile", subtitle: "Create a secure OPC UA endpoint profile", systemImage: "plus.circle", tint: .blue)]
            }
            return appState.servers.map { server in
                EnterpriseWorkspaceItem(
                    id: server.id.uuidString,
                    title: server.name,
                    subtitle: "\(server.endpoint) - \(server.securityMode.rawValue) / \(server.securityPolicy.displayName)",
                    systemImage: server.status.systemImage,
                    tint: server.status.color
                )
            }
        case .browse:
            return [
                EnterpriseWorkspaceItem(id: "tree", title: "Tree Browser", subtitle: "Lazy browse children and inspect namespaces", systemImage: "list.bullet.indent", tint: .blue),
                EnterpriseWorkspaceItem(id: "search", title: "Flat Search Results", subtitle: "Filter by node class, access level, and namespace", systemImage: "magnifyingglass", tint: .teal),
                EnterpriseWorkspaceItem(id: "inspector", title: "Node Detail Inspector", subtitle: "Attributes, references, value, history, events, and raw details", systemImage: "sidebar.right", tint: .indigo)
            ]
        case .readWrite:
            return [
                EnterpriseWorkspaceItem(id: "batch-read", title: "Batch Read", subtitle: "Read selected nodes with timestamps and status codes", systemImage: "arrow.down.doc", tint: .green),
                EnterpriseWorkspaceItem(id: "typed-write", title: "Type-Aware Write", subtitle: "Validate, confirm, write, and audit value changes", systemImage: "square.and.pencil", tint: .orange),
                EnterpriseWorkspaceItem(id: "methods", title: "Method Calls", subtitle: "Inspect arguments and execute saved method presets", systemImage: "function", tint: .purple)
            ]
        case .subscriptions:
            return appState.subscriptions.isEmpty ? [
                EnterpriseWorkspaceItem(id: "new-subscription", title: "Create Subscription", subtitle: "Build a publishing container for monitored items", systemImage: "plus.circle", tint: .blue)
            ] : appState.subscriptions.map { subscription in
                EnterpriseWorkspaceItem(
                    id: subscription.id.uuidString,
                    title: subscription.name,
                    subtitle: "\(subscription.monitoredItems.count) monitored item\(subscription.monitoredItems.count == 1 ? "" : "s")",
                    systemImage: "bell.badge",
                    tint: .orange
                )
            }
        case .monitor:
            return [
                EnterpriseWorkspaceItem(id: "table", title: "Live Table", subtitle: "Raw values, quality, and timestamps", systemImage: "tablecells", tint: .green),
                EnterpriseWorkspaceItem(id: "trend", title: "Trend", subtitle: "Pinned values and threshold overlays", systemImage: "chart.line.uptrend.xyaxis", tint: .blue),
                EnterpriseWorkspaceItem(id: "watchlists", title: "Watchlists", subtitle: "Reusable multi-server operational views", systemImage: "pin", tint: .orange)
            ]
        case .analytics:
            return [
                EnterpriseWorkspaceItem(id: "trends", title: "Trends", subtitle: "Live values and historical samples for selected nodes", systemImage: "chart.xyaxis.line", tint: .blue),
                EnterpriseWorkspaceItem(id: "comparison", title: "Comparison", subtitle: "Compare selected variables across assets and servers", systemImage: "rectangle.split.3x1", tint: .purple),
                EnterpriseWorkspaceItem(id: "export", title: "Analytics Export", subtitle: "Export collected analytics samples", systemImage: "square.and.arrow.up", tint: .green)
            ]
        case .alarms:
            return [
                EnterpriseWorkspaceItem(id: "active", title: "Active Conditions", subtitle: "Retain, acked, confirmed, shelved, severity", systemImage: "exclamationmark.triangle", tint: .red),
                EnterpriseWorkspaceItem(id: "event-stream", title: "Event Stream", subtitle: "Filter and export event notifications", systemImage: "waveform.path", tint: .orange),
                EnterpriseWorkspaceItem(id: "condition-refresh", title: "Condition Refresh", subtitle: "Reconnect recovery and state reconciliation", systemImage: "arrow.clockwise.circle", tint: .blue)
            ]
        case .history:
            return HistoryWorkspaceView.sidebarItems
        case .diagnostics:
            return [
                EnterpriseWorkspaceItem(id: "timeline", title: "Connection Timeline", subtitle: "Connect, secure channel, session, service calls", systemImage: "timeline.selection", tint: .blue),
                EnterpriseWorkspaceItem(id: "service-calls", title: "Service Calls", subtitle: "Timing, status codes, endpoint, security mode", systemImage: "list.bullet.rectangle", tint: .purple),
                EnterpriseWorkspaceItem(id: "network-trace", title: "Network Trace", subtitle: "OPC UA message flow, bytes, directions, and hex preview", systemImage: "point.3.connected.trianglepath.dotted", tint: .teal),
                EnterpriseWorkspaceItem(id: "bundle", title: "Export Bundle", subtitle: "Package logs and protocol details for support", systemImage: "shippingbox", tint: .green)
            ]
        case .security:
            return SecurityWorkspaceView.sidebarItems
        case .reports:
            return ReportsWorkspaceView.sidebarItems
        case .settings:
            return [
                EnterpriseWorkspaceItem(id: "app", title: "Application", subtitle: "General application preferences", systemImage: "gearshape", tint: .gray),
                EnterpriseWorkspaceItem(id: "storage", title: "Storage", subtitle: "Database and configuration storage", systemImage: "externaldrive", tint: .blue)
            ]
        }
    }
}

private struct OPCUASessionRequiredView: View {
    @EnvironmentObject var appState: AppState
    let workspace: AppState.MainTab

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "network.slash")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Connect to an OPC UA Server")
                .font(.title2.weight(.semibold))

            Text("\(workspace.rawValue) uses live OPC UA services and is locked until a server session is active.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            HStack {
                Button {
                    appState.selectedTab = .servers
                } label: {
                    Label("Open Servers", systemImage: "server.rack")
                }

                Button {
                    appState.showingServerConnection = true
                } label: {
                    Label("New Connection", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle(workspace.rawValue)
    }
}

struct ModernConnectionOverlay: View {
    let serverName: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)

                Text("Connecting\(serverName.map { " to \($0)" } ?? "")")
                    .font(.headline)

                Text("Establishing session and security context.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 12)
        }
        .allowsHitTesting(true)
    }
}

#Preview {
    ModernMainView()
        .environmentObject(AppState())
}
