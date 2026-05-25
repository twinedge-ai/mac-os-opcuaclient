import SwiftUI
import UniformTypeIdentifiers

struct ServerConfigurationView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState

    let server: OPCUAServer?

    @State private var name = ""
    @State private var networkSchema: NetworkSchema = .opcTcp
    @State private var host = ""
    @State private var port = ""
    @State private var serverDescription = ""
    @State private var securityMode: SecurityMode = .none
    @State private var securityPolicy: SecurityPolicy = .none
    @State private var authMode: AuthenticationMode = .anonymous
    @State private var username = ""
    @State private var password = ""
    @State private var certificatePath = ""
    @State private var privateKeyPath = ""
    @State private var serverCertificatePath = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?

    struct TestResult {
        let success: Bool
        let message: String
        let hints: [String]
    }

    init(server: OPCUAServer?) {
        self.server = server
    }

    /// Computed endpoint URL for display
    var endpointPreview: String {
        let portValue = Int(port) ?? networkSchema.defaultPort
        let hostValue = host.isEmpty ? "hostname" : host
        return "\(networkSchema.prefix)\(hostValue):\(portValue)"
    }

    enum FilePickerType: Identifiable {
        case certificate
        case privateKey
        case serverCertificate
        
        var id: Int { hashValue }
    }

    @State private var activePicker: FilePickerType?
    @State private var isImporterPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Server Name") {
                        TextField("", text: $name, prompt: Text("My OPC UA Server"))
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent("Description") {
                        TextField("", text: $serverDescription, prompt: Text("Optional description"), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                    }
                } header: {
                    Text("Server Information")
                }

                Section {
                    LabeledContent("Protocol") {
                        Picker("", selection: $networkSchema) {
                            ForEach(NetworkSchema.allCases) { schema in
                                Text(schema.displayName).tag(schema)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(minWidth: 180)
                        .onChange(of: networkSchema) { _, newValue in
                            // Update port to default for the selected schema if port is empty or was default
                            if port.isEmpty || port == String(NetworkSchema.opcTcp.defaultPort) || port == String(NetworkSchema.opcWss.defaultPort) {
                                port = String(newValue.defaultPort)
                            }
                        }
                    }

                    LabeledContent("Host") {
                        TextField("", text: $host, prompt: Text("localhost"))
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                    }

                    LabeledContent("Port") {
                        TextField("", text: $port, prompt: Text("\(networkSchema.defaultPort)"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }

                    // Endpoint Preview
                    HStack {
                        Text("Endpoint URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(endpointPreview)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    LabeledContent("Security Mode") {
                        Picker("", selection: $securityMode) {
                            ForEach(SecurityMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    LabeledContent("Security Policy") {
                        Picker("", selection: $securityPolicy) {
                            ForEach(SecurityPolicy.allCases) { policy in
                                Text(policy.displayName).tag(policy)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                } header: {
                    Text("Connection")
                }

                Section {
                    LabeledContent("Authentication") {
                        Picker("", selection: $authMode) {
                            ForEach(AuthenticationMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 180)
                    }

                    if authMode == .usernamePassword {
                        LabeledContent("Username") {
                            TextField("", text: $username, prompt: Text("Username"))
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.username)
                        }

                        LabeledContent("Password") {
                            SecureField("", text: $password, prompt: Text("Password"))
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.password)
                        }
                    }

                    if authMode == .certificate {
                        LabeledContent("Certificate") {
                            HStack {
                                TextField("", text: $certificatePath, prompt: Text("Certificate Path"))
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(true)

                                Button("Browse...") {
                                    activePicker = .certificate
                                    isImporterPresented = true
                                }
                            }
                        }
                    }

                    if authMode == .certificate || securityMode != .none {
                        LabeledContent("Private Key") {
                            HStack {
                                TextField("", text: $privateKeyPath, prompt: Text("Private Key Path"))
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(true)

                                Button("Browse...") {
                                    activePicker = .privateKey
                                    isImporterPresented = true
                                }
                            }
                        }

                        LabeledContent("Server Certificate") {
                            HStack {
                                TextField("", text: $serverCertificatePath, prompt: Text("Server Certificate Path"))
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(true)

                                Button("Browse...") {
                                    activePicker = .serverCertificate
                                    isImporterPresented = true
                                }
                            }
                        }
                    }
                } header: {
                    Text("Authentication")
                }

                Section {
                    VStack(alignment: .center, spacing: 12) {
                        Button(action: testConnection) {
                            HStack {
                                if isTesting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "network.badge.shield.half.filled")
                                }
                                Text(isTesting ? "Testing..." : "Test Connection")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(name.isEmpty || host.isEmpty || isTesting)

                        if let result = testResult {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(result.success ? .green : .red)
                                    Text(result.message)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                if !result.hints.isEmpty {
                                    ForEach(result.hints, id: \.self) { hint in
                                        Text("• \(hint)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                } header: {
                    Text("Connection Test")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(server == nil ? "Add Server" : "Edit Server")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveServer()
                    }
                    .disabled(name.isEmpty || host.isEmpty)
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.item], // Allows checking for any file, can refine to x509Certificate later if UTType is available
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    
                    // Request access to the security-scoped resource
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        
                        // AppState persists this path as a security-scoped
                        // bookmark when the server profile is saved.
                        let path = url.path
                        
                        switch activePicker {
                        case .certificate:
                            certificatePath = path
                        case .privateKey:
                            privateKeyPath = path
                        case .serverCertificate:
                            serverCertificatePath = path
                        case .none:
                            break
                        }
                    } else {
                        // Fallback if access fails (e.g. not sandboxed or file is public)
                         let path = url.path
                        switch activePicker {
                        case .certificate:
                            certificatePath = path
                        case .privateKey:
                            privateKeyPath = path
                        case .serverCertificate:
                            serverCertificatePath = path
                        case .none:
                            break
                        }
                    }
                case .failure(let error):
                    print("File import failed: \(error.localizedDescription)")
                }
            }
        }
        .onAppear {
            if let server = server {
                name = server.name
                networkSchema = server.networkSchema
                host = server.host
                port = String(server.port)
                serverDescription = server.description
                securityMode = server.securityMode
                securityPolicy = server.securityPolicy
                authMode = server.authenticationMode
                username = server.username ?? ""
                password = server.password ?? ""
                certificatePath = server.certificatePath ?? ""
                privateKeyPath = server.privateKeyPath ?? ""
                serverCertificatePath = server.serverCertificatePath ?? ""
            } else {
                // Set default port for new servers
                port = String(networkSchema.defaultPort)
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
    }

    func testConnection() {
        isTesting = true
        testResult = nil

        let portValue = Int(port) ?? networkSchema.defaultPort

        // Create temporary server config to test
        let testServer = OPCUAServer(
            name: name.isEmpty ? "Test" : name,
            networkSchema: networkSchema,
            host: host,
            port: portValue,
            securityMode: securityMode,
            securityPolicy: securityPolicy,
            authenticationMode: authMode,
            username: authMode == .usernamePassword ? username : nil,
            password: authMode == .usernamePassword ? password : nil,
            certificatePath: certificatePath.isEmpty ? nil : certificatePath,
            privateKeyPath: privateKeyPath.isEmpty ? nil : privateKeyPath,
            serverCertificatePath: serverCertificatePath.isEmpty ? nil : serverCertificatePath,
            status: .disconnected,
            lastConnected: nil,
            description: ""
        )

        Task {
            let success = await appState.connectionManager.connectToServer(testServer)
            let errorDetail = appState.connectionManager.getLastError(for: testServer)

            // Disconnect after test
            if success {
                appState.connectionManager.disconnectFromServer(testServer)
            }

            await MainActor.run {
                isTesting = false
                testResult = TestResult(
                    success: success,
                    message: success ? "Connection successful - server is reachable" : (errorDetail?.message ?? "Failed to connect"),
                    hints: success ? [] : (errorDetail?.hints ?? [])
                )
            }
        }
    }

    func saveServer() {
        let portValue = Int(port) ?? networkSchema.defaultPort

        let newServer = OPCUAServer(
            id: server?.id ?? UUID(),
            name: name,
            networkSchema: networkSchema,
            host: host,
            port: portValue,
            securityMode: securityMode,
            securityPolicy: securityPolicy,
            authenticationMode: authMode,
            username: authMode == .usernamePassword ? username : nil,
            password: authMode == .usernamePassword ? password : nil,
            certificatePath: certificatePath.isEmpty ? nil : certificatePath,
            privateKeyPath: privateKeyPath.isEmpty ? nil : privateKeyPath,
            serverCertificatePath: serverCertificatePath.isEmpty ? nil : serverCertificatePath,
            status: .disconnected,
            lastConnected: server?.lastConnected,
            description: serverDescription
        )

        // Save to SwiftData persistent storage
        appState.saveServer(newServer)

        dismiss()
    }
}

struct ServerDetailView: View {
    let server: OPCUAServer
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ServerInfoCard(server: server)
                    ConnectionInfoCard(server: server)
                    SecurityInfoCard(server: server)
                    ServerStatisticsCard(server: server)
                }
                .padding()
            }
            .navigationTitle(server.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
    }
}

struct ServerInfoCard: View {
    let server: OPCUAServer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Server Information", systemImage: "info.circle.fill")
                .font(.headline)

            Divider()

            DetailRow(label: "Name", value: server.name)
            DetailRow(label: "Description", value: server.description)
            DetailRow(label: "Status", value: server.status.rawValue, color: server.status.color)
        }
        .cardStyle()
    }
}

struct ConnectionInfoCard: View {
    let server: OPCUAServer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Connection Details", systemImage: "network")
                .font(.headline)

            Divider()

            DetailRow(label: "Protocol", value: server.networkSchema.displayName)
            DetailRow(label: "Host", value: server.host)
            DetailRow(label: "Port", value: String(server.port))
            DetailRow(label: "Endpoint", value: server.endpoint)
            if let lastConnected = server.lastConnected {
                DetailRow(label: "Last Connected", value: lastConnected.formatted())
            }
        }
        .cardStyle()
    }
}

struct SecurityInfoCard: View {
    let server: OPCUAServer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Security Configuration", systemImage: "lock.shield.fill")
                .font(.headline)

            Divider()

            DetailRow(label: "Security Mode", value: server.securityMode.rawValue)
            DetailRow(label: "Security Policy", value: server.securityPolicy.displayName)
            DetailRow(label: "Authentication", value: server.authenticationMode.rawValue)
            if let username = server.username {
                DetailRow(label: "Username", value: username)
            }
            if let certificatePath = server.certificatePath {
                DetailRow(label: "Certificate", value: certificatePath)
            }
        }
        .cardStyle()
    }
}

struct ServerStatisticsCard: View {
    let server: OPCUAServer
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Statistics", systemImage: "chart.bar.fill")
                .font(.headline)

            Divider()

            let isConnected = appState.connectionManager.getConnectionStatus(for: server) == .connected

            if isConnected {
                DetailRow(label: "Status", value: "Connected", color: .green)
                DetailRow(label: "Active Subscriptions", value: "0")
                DetailRow(label: "Monitored Items", value: "0")
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No statistics available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Connect to server to view statistics")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                    Spacer()
                }
            }
        }
        .cardStyle()
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondarySystemGroupedBackground)
            )
    }
}
