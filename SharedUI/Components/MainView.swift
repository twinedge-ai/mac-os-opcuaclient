import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        #if os(iOS)
        ZStack {
            TabView(selection: $appState.selectedTab) {
                ForEach(AppState.MainTab.allCases) { tab in
                    NavigationStack {
                        tabContent(for: tab)
                    }
                    .tabItem {
                        Label(tab.rawValue, systemImage: tab.systemImage)
                    }
                    .tag(tab)
                }
            }
            if appState.isConnecting {
                ConnectionBlockingOverlay(serverName: appState.connectingServerName)
            }
        }
        .sheet(isPresented: $appState.showingDatabaseManagement) {
            DatabaseManagementView()
        }
        .sheet(isPresented: $appState.showingServerConnection) {
            ServerConfigurationView(server: nil)
        }
        #else
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
            } detail: {
                NavigationStack {
                    tabContent(for: appState.selectedTab)
                }
            }
            .navigationSplitViewStyle(.balanced)
            if appState.isConnecting {
                ConnectionBlockingOverlay(serverName: appState.connectingServerName)
            }
        }
        .sheet(isPresented: $appState.showingDatabaseManagement) {
            DatabaseManagementView()
        }
        .sheet(isPresented: $appState.showingServerConnection) {
            ServerConfigurationView(server: nil)
        }
        #endif
    }

    @ViewBuilder
    func tabContent(for tab: AppState.MainTab) -> some View {
        switch tab {
        case .servers:
            ServerListView()
        case .browse:
            AddressSpaceBrowser()
        case .readWrite:
            ReadWriteWorkspaceView()
        case .subscriptions:
            SubscriptionsView()
        case .monitor:
            MonitoringDashboard()
        case .analytics:
            AnalyticsView()
        case .alarms:
            AlarmEventManagementView()
        case .history:
            HistoryWorkspaceView()
        case .diagnostics:
            DiagnosticsView()
        case .security:
            SecurityWorkspaceView()
        case .reports:
            ReportsWorkspaceView()
        case .settings:
            SettingsView()
        }
    }
}

struct ConnectionBlockingOverlay: View {
    let serverName: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)

                Text("Connecting\(serverName.map { " to \($0)" } ?? "")")
                    .font(.headline)

                Text("Please wait until the session is ready.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondarySystemGroupedBackground)
                    .shadow(radius: 8)
            )
        }
        .allowsHitTesting(true)
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedTab: AppState.MainTab = .servers
    @State private var showingAddServer = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedTab) {
                Section("Navigation") {
                    ForEach(AppState.MainTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }

                if !appState.servers.isEmpty {
                    Section("Connected Servers") {
                        ForEach(appState.servers.filter { $0.status == .connected }) { server in
                            ServerRow(server: server, isCompact: true)
                        }
                    }
                }
            }
            .listStyle(SidebarListStyle())

            // Quick Actions as separate buttons outside the List
            VStack(spacing: 8) {
                Text("Quick Actions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                Button(action: {
                    showingAddServer = true
                }) {
                    Label("Add Server", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

                Button(action: {}) {
                    Label("Import Config", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .padding(.vertical, 12)
            .background(Color.windowBackgroundColor)
        }
        .searchable(text: $searchText, placement: .sidebar)
        .navigationTitle("OPC UA Client")
        .sheet(isPresented: $showingAddServer) {
            ServerConfigurationView(server: nil)
        }
        .onAppear {
            selectedTab = appState.selectedTab
        }
        .onChange(of: selectedTab) { _, newValue in
            Task { @MainActor in
                appState.selectedTab = newValue
            }
        }
        .onChange(of: appState.selectedTab) { _, newValue in
            if selectedTab != newValue {
                selectedTab = newValue
            }
        }
    }

    func toggleSidebar() {
        #if os(macOS)
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
        #endif
    }
}

struct ServerRow: View {
    let server: OPCUAServer
    var isCompact: Bool = false

    var body: some View {
        HStack {
            Image(systemName: server.status.systemImage)
                .foregroundColor(server.status.color)
                .font(.system(size: isCompact ? 10 : 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(isCompact ? .caption : .body)
                    .fontWeight(.medium)

                if !isCompact {
                    Text(server.endpoint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, isCompact ? 2 : 4)
    }
}

#Preview {
    MainView()
        .environmentObject(AppState())
}
