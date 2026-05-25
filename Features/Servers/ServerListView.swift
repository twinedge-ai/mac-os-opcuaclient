import SwiftUI
import Combine
import UniformTypeIdentifiers

struct ServerListView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingAddServer = false
    @State private var selectedServer: OPCUAServer?
    @State private var searchText = ""
    @State private var showingProfiles = false
    @State private var showingDiscovery = false
    @State private var showingImportConfiguration = false
    @State private var showingExportConfiguration = false
    @State private var configurationDocument: ConfigurationDocument?
    @State private var configurationError: String?

    var filteredServers: [OPCUAServer] {
        if searchText.isEmpty {
            return appState.servers
        }
        return appState.servers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.endpoint.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            if appState.servers.isEmpty {
                EmptyStateView()
            } else {
                ServerGrid()
            }
        }
        .navigationTitle("OPC UA Servers")
        .searchable(text: $searchText, prompt: "Search servers...")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Button(action: { showingAddServer = true }) {
                        Label("Add Server", systemImage: "plus")
                    }
                    Button(action: { showingProfiles = true }) {
                        Label("Connection Profiles", systemImage: "bookmark")
                    }
                    Button(action: { exportConfiguration() }) {
                        Label("Export Configuration", systemImage: "square.and.arrow.up")
                    }
                    Button(action: { showingImportConfiguration = true }) {
                        Label("Import Configuration", systemImage: "square.and.arrow.down")
                    }
                    Divider()
                    Button(action: { showingDiscovery = true }) {
                        Label("Scan Network", systemImage: "wifi")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }

                Button(action: refreshServers) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .sheet(isPresented: $showingAddServer) {
            ServerConfigurationView(server: nil)
        }
        .sheet(isPresented: $showingProfiles) {
            ConnectionProfilesView()
        }
        .sheet(isPresented: $showingDiscovery) {
            DiscoveryScanView()
        }
        .fileImporter(
            isPresented: $showingImportConfiguration,
            allowedContentTypes: [.json]
        ) { result in
            handleImport(result: result)
        }
        .fileExporter(
            isPresented: $showingExportConfiguration,
            document: configurationDocument,
            contentType: .json,
            defaultFilename: "opcua-client-configuration"
        ) { result in
            if case .failure(let error) = result {
                configurationError = "Export failed: \(error.localizedDescription)"
            }
        }
        .alert("Configuration", isPresented: Binding<Bool>(
            get: { configurationError != nil },
            set: { _ in configurationError = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(configurationError ?? "Unknown error")
        }
        .sheet(item: $selectedServer) { server in
            ServerDetailView(server: server)
        }
    }

    @ViewBuilder
    func ServerGrid() -> some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)
            ], spacing: 16) {
                ForEach(filteredServers) { server in
                    ServerCard(server: server) {
                        selectedServer = server
                    }
                }
            }
            .padding()
        }
    }

    func refreshServers() {
        // Notify UI to update connection statuses
        NotificationCenter.default.post(name: .opcuaConnectionChanged, object: nil)
    }

    private func exportConfiguration() {
        let bundle = appState.exportConfiguration()
        configurationDocument = ConfigurationDocument(bundle: bundle)
        showingExportConfiguration = true
    }

    private func handleImport(result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let data = try Data(contentsOf: url)
            let bundle = try ConfigurationCodec.decode(data)
            appState.importConfiguration(bundle)
        } catch {
            configurationError = "Import failed: \(error.localizedDescription)"
        }
    }
}

struct EmptyStateView: View {
    @State private var showingAddServer = false
    @State private var showingDiscovery = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 72))
                .foregroundColor(.secondary)
                .symbolEffect(.pulse)

            Text("No Servers Configured")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add your first OPC UA server to get started")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(action: { showingAddServer = true }) {
                    Label("Add Server", systemImage: "plus.circle.fill")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: { showingDiscovery = true }) {
                    Label("Scan Network", systemImage: "wifi")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding()
        .sheet(isPresented: $showingAddServer) {
            ServerConfigurationView(server: nil)
        }
        .sheet(isPresented: $showingDiscovery) {
            DiscoveryScanView()
        }
    }
}

struct ServerCard: View {
    let server: OPCUAServer
    let action: () -> Void
    @State private var isHovered = false
    @State private var isConnecting = false
    @State private var connectionStatus: ConnectionStatus = .disconnected
    @State private var connectionQuality: ConnectionQuality = .unknown
    @State private var connectionError: ConnectionErrorDetail?
    @State private var showingErrorAlert = false
    @State private var showingEditSheet = false
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            serverHeader
            Divider()
            serverDetails

            if let lastConnected = server.lastConnected {
                Divider()
                lastConnectionInfo(lastConnected)
            }

            // Show error message if connection failed
            if connectionStatus == .error, let error = connectionError {
                Divider()
                errorInfo(error)
            }

            actionButtons
        }
        .padding()
        .background(cardBackground)
        .overlay(cardOverlay)
        .scaleEffect(isHovered ? 1.02 : 1)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            action()
        }
        .onAppear {
            updateConnectionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .opcuaConnectionChanged)) { _ in
            updateConnectionStatus()
        }
        .alert("Connection Failed", isPresented: $showingErrorAlert) {
            if let error = connectionError {
                if error.actions.contains(.retryConnection) {
                    Button(ConnectionRecoveryAction.retryConnection.title) {
                        connectToServer()
                    }
                }
                if error.actions.contains(.editServer) {
                    Button(ConnectionRecoveryAction.editServer.title) {
                        showingEditSheet = true
                    }
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(connectionError?.formattedMessage ?? "Unknown error")
        }
        .sheet(isPresented: $showingEditSheet) {
            ServerConfigurationView(server: server)
        }
    }

    private func updateConnectionStatus() {
        let newStatus = appState.connectionManager.getConnectionStatus(for: server)
        if connectionStatus != newStatus {
            connectionStatus = newStatus
        }
        connectionQuality = appState.connectionManager.getConnectionQuality(for: server)
        // Update error message if present
        if let error = appState.connectionManager.getLastError(for: server) {
            connectionError = error
        } else {
            connectionError = nil
        }
    }

    var displayedConnectionStatus: ConnectionStatus {
        if isConnecting {
            return .connecting
        }
        return connectionStatus
    }

    var serverHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(server.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if server.isDefault {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                            .help("Default Server")
                    }
                    
                    Spacer()
                }

                HStack(spacing: 4) {
                    Image(systemName: displayedConnectionStatus.systemImage)
                        .font(.caption)
                    Text(displayedConnectionStatus.rawValue)
                        .font(.caption)
                }
                .foregroundColor(displayedConnectionStatus.color)
            }

            Spacer()

            serverMenu
        }
    }

    var serverMenu: some View {
        Menu {
            Button(action: { action() }) {
                Label("View Details", systemImage: "info.circle")
            }
            Button(action: { connectToServer() }) {
                Label("Connect", systemImage: "link")
            }
            .disabled(displayedConnectionStatus == .connected || isConnecting)
            Button(action: { disconnectFromServer() }) {
                Label("Disconnect", systemImage: "minus.circle")
            }
            .disabled(displayedConnectionStatus != .connected)
            Button(action: { browseServer() }) {
                Label("Browse Address Space", systemImage: "folder.fill.badge.gearshape")
            }
            Divider()
            Button(action: { showingEditSheet = true }) {
                Label("Edit", systemImage: "pencil")
            }
            Button(action: { duplicateServer() }) {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            Button(action: { setAsDefault() }) {
                Label(server.isDefault ? "Default Server" : "Set as Default", systemImage: server.isDefault ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .disabled(server.isDefault)
            Divider()
            Button(role: .destructive, action: { deleteServer() }) {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .symbolRenderingMode(.hierarchical)
                .font(.title3)
        }
        .buttonStyle(.plain)
    }

    func connectToServer() {
        guard !isConnecting else { return }

        isConnecting = true
        connectionError = nil  // Clear previous error
        Task { @MainActor in
            appState.beginConnectionProgress(serverName: server.name)
        }

        Task {
            let success = await appState.connectionManager.connectToServer(server)

            await MainActor.run {
                isConnecting = false
                if success {
                    connectionStatus = .connected
                    connectionError = nil
                } else {
                    connectionStatus = .error
                    // Get the error message from the connection manager
                    connectionError = appState.connectionManager.getLastError(for: server)
                    showingErrorAlert = true
                }
                appState.endConnectionProgress()
            }
        }
    }

    func disconnectFromServer() {
        appState.connectionManager.disconnectFromServer(server)
        connectionStatus = .disconnected
        connectionError = nil
    }

    func browseServer() {
        // Defer state changes to next run loop to avoid "Publishing changes from within view updates" error
        Task { @MainActor in
            appState.selectedServer = server
            appState.selectedTab = .browse
        }
    }

    func duplicateServer() {
        let newServer = OPCUAServer(
            name: "\(server.name) (Copy)",
            networkSchema: server.networkSchema,
            host: server.host,
            port: server.port,
            securityMode: server.securityMode,
            authenticationMode: server.authenticationMode,
            username: server.username,
            password: server.password,
            status: .disconnected,
            lastConnected: nil,
            description: server.description
        )
        Task { @MainActor in
            appState.saveServer(newServer)
        }
    }

    func setAsDefault() {
        appState.setServerAsDefault(server)
    }
    
    func deleteServer() {
        // Disconnect if connected
        if connectionStatus == .connected {
            disconnectFromServer()
        }
        Task { @MainActor in
            appState.deleteServer(server)
        }
    }

    var serverDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(server.endpoint, systemImage: "network")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Label("Port \(server.port)", systemImage: "number.circle")
                .font(.caption)
                .foregroundColor(.secondary)

            Label(server.securityMode.rawValue, systemImage: "lock.shield")
                .font(.caption)
                .foregroundColor(.secondary)

            if server.status == .connected && connectionQuality == .unknown {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                    Text("Calibrating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Label(connectionQuality.rawValue, systemImage: connectionQuality.systemImage)
                    .font(.caption)
                    .foregroundColor(connectionQuality.color)
            }
        }
    }

    func lastConnectionInfo(_ date: Date) -> some View {
        Label {
            Text("Last connected \(date, format: .relative(presentation: .named))")
                .font(.caption2)
                .foregroundColor(.secondary)
        } icon: {
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    func errorInfo(_ detail: ConnectionErrorDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)

                Text(detail.message)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)
            }

            if !detail.hints.isEmpty {
                ForEach(detail.hints, id: \.self) { hint in
                    Text("• \(hint)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color.red.opacity(0.1))
        .cornerRadius(6)
    }

    var actionButtons: some View {
        HStack(spacing: 8) {
            Button(action: { browseServer() }) {
                Label("Browse", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            #if os(iOS)
            .buttonStyle(.bordered)
            #endif
            .controlSize(.small)

            if displayedConnectionStatus == .connected {
                Button(action: { disconnectFromServer() }) {
                    Label("Disconnect", systemImage: "minus.circle")
                        .frame(maxWidth: .infinity)
                }
                #if os(macOS)
                .buttonStyle(.automatic)
                #else
                .buttonStyle(.bordered)
                #endif
                .controlSize(.small)
            } else {
                Button(action: { connectToServer() }) {
                    Label(isConnecting ? "Connecting..." : "Connect", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                #if os(macOS)
                .buttonStyle(.automatic)
                #else
                .buttonStyle(.borderedProminent)
                #endif
                .controlSize(.small)
            }
        }
    }

    var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.secondarySystemGroupedBackground)
            .shadow(color: .black.opacity(isHovered ? 0.15 : 0.05), radius: isHovered ? 8 : 4, y: 2)
    }

    var cardOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(server.status.color.opacity(server.status == .connected ? 0.5 : 0), lineWidth: 2)
    }
}
