import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct ModernServerConfigurationView: View {
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
    @State private var applicationURI = ClientApplicationURI.installDefault
    @State private var requestedTimeout = "10"
    @State private var sessionTimeout = "60"
    @State private var localeIDs = ""
    @State private var keepalivePolicy: KeepalivePolicy = .standard
    @State private var reconnectPolicy: ReconnectPolicy = .automaticWithBackoff
    @State private var trustBehavior: ProfileTrustBehavior = .blockUnknown
    @State private var tags = ""
    @State private var notes = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?
    
    // File picker states
    @State private var showingCertificatePicker = false
    @State private var showingPrivateKeyPicker = false
    @State private var showingServerCertificatePicker = false
    @State private var showingAdvancedSettings = false
    @State private var selectedTab = 0
    
    struct TestResult {
        let success: Bool
        let message: String
        let hints: [String]
        let report: ConnectionTestReport
    }
    
    init(server: OPCUAServer?) {
        self.server = server
    }
    
    var endpointPreview: String {
        let portValue = Int(port) ?? networkSchema.defaultPort
        let hostValue = host.isEmpty ? "hostname" : host
        return "\(networkSchema.prefix)\(hostValue):\(portValue)"
    }
    
    var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Int(port) != nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Modern Header
            DialogHeader(
                title: server == nil ? "Add Server" : "Edit Server",
                subtitle: server == nil ? "Configure a new OPC UA server connection" : "Modify server configuration",
                icon: "server.rack",
                onDismiss: { dismiss() }
            )
            
            // Tab Selection
            Picker("", selection: $selectedTab) {
                Label("Basic", systemImage: "network").tag(0)
                Label("Security", systemImage: "lock.shield").tag(1)
                Label("Advanced", systemImage: "gearshape.2").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(DesignSystem.Spacing.medium)
            .padding(.horizontal, DesignSystem.Spacing.large)
            
            // Content
            TabView(selection: $selectedTab) {
                basicSettingsTab
                    .tag(0)
                
                securitySettingsTab
                    .tag(1)
                
                advancedSettingsTab
                    .tag(2)
            }
            #if os(macOS)
            .tabViewStyle(.automatic)
            #endif
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Connection Test Result
            if let result = testResult {
                connectionTestResultView(result)
            }
            
            // Footer Actions
            DialogFooter(
                primaryAction: saveServer,
                primaryLabel: server == nil ? "Add Server" : "Save Changes",
                cancelAction: { dismiss() },
                isPrimaryDisabled: !isFormValid
            )
        }
        .frame(width: 700, height: 600)
        .background(DesignSystem.Colors.background)
        .onAppear {
            loadServerData()
        }
    }
    
    // MARK: - Basic Settings Tab
    
    var basicSettingsTab: some View {
        ModernForm {
            FormSection("Server Identity") {
                ModernTextField(
                    title: "Server Name",
                    text: $name,
                    icon: "tag",
                    placeholder: "My OPC UA Server"
                )
                
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                    HStack(spacing: DesignSystem.Spacing.xxSmall) {
                        Image(systemName: "text.alignleft")
                            .foregroundColor(DesignSystem.Colors.primary)
                            .font(.system(size: 12, weight: .medium))
                        Text("DESCRIPTION")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                    
                    TextEditor(text: $serverDescription)
                        .font(DesignSystem.Typography.body)
                        .padding(DesignSystem.Spacing.small)
                        .frame(height: 80)
                        .background(Color.gray.opacity(0.06))
                        .cornerRadius(DesignSystem.CornerRadius.small)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                .stroke(DesignSystem.Colors.borderLight, lineWidth: 1)
                        )
                }
            }
            
            FormSection("Connection Details") {
                ModernPicker(
                    "Protocol",
                    selection: $networkSchema,
                    icon: "network"
                ) {
                    ForEach(NetworkSchema.allCases) { schema in
                        HStack {
                            Image(systemName: schema == .opcTcp ? "network" : "lock.icloud")
                                .foregroundColor(DesignSystem.Colors.primary)
                            Text(schema.displayName)
                        }
                        .tag(schema)
                    }
                }
                .onChange(of: networkSchema) { _, newValue in
                    if port.isEmpty || port == String(NetworkSchema.opcTcp.defaultPort) || 
                       port == String(NetworkSchema.opcWss.defaultPort) {
                        port = String(newValue.defaultPort)
                    }
                }
                
                HStack(spacing: DesignSystem.Spacing.medium) {
                    ModernTextField(
                        title: "Host Address",
                        text: $host,
                        icon: "globe",
                        placeholder: "localhost or IP address"
                    )
                    
                    ModernTextField(
                        title: "Port",
                        text: $port,
                        icon: "number",
                        placeholder: String(networkSchema.defaultPort)
                    )
                    .frame(maxWidth: 120)
                }
                
                // Endpoint Preview
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                    HStack(spacing: DesignSystem.Spacing.xxSmall) {
                        Image(systemName: "link")
                            .foregroundColor(DesignSystem.Colors.info)
                            .font(.system(size: 12, weight: .medium))
                        Text("ENDPOINT PREVIEW")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                    
                    Text(endpointPreview)
                        .font(DesignSystem.Typography.monospacedBody)
                        .foregroundColor(DesignSystem.Colors.primary)
                        .padding(DesignSystem.Spacing.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                .fill(DesignSystem.Colors.primary.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                        .stroke(DesignSystem.Colors.primary.opacity(0.2), lineWidth: 1)
                                )
                        )
                }
                
                // Test Connection Button
                Button(action: testConnection) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "network")
                        }
                        Text(isTesting ? "Testing Connection..." : "Test Connection")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isTesting || !isFormValid)
            }
        }
    }
    
    // MARK: - Security Settings Tab
    
    var securitySettingsTab: some View {
        ModernForm {
            FormSection("Security Configuration") {
                ModernPicker(
                    "Security Mode",
                    selection: $securityMode,
                    icon: "lock"
                ) {
                    ForEach(SecurityMode.allCases) { mode in
                        HStack {
                            Image(systemName: mode == .none ? "lock.open" : "lock.fill")
                                .foregroundColor(mode == .none ? .orange : .green)
                            Text(mode.rawValue)
                        }
                        .tag(mode)
                    }
                }
                
                if securityMode != .none {
                    ModernPicker(
                        "Security Policy",
                        selection: $securityPolicy,
                        icon: "shield"
                    ) {
                        ForEach(SecurityPolicy.allCases) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                }
                
                // Security Info
                if securityMode != .none {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(DesignSystem.Colors.info)
                        Text("Secure connection requires valid certificates and may impact performance")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                    .padding(DesignSystem.Spacing.small)
                    .background(DesignSystem.Colors.info.opacity(0.1))
                    .cornerRadius(DesignSystem.CornerRadius.small)
                }
            }
            
            FormSection("Authentication") {
                ModernPicker(
                    "Authentication Mode",
                    selection: $authMode,
                    icon: "person.badge.key"
                ) {
                    ForEach(AuthenticationMode.allCases) { mode in
                        HStack {
                            Image(systemName: authModeIcon(mode))
                                .foregroundColor(DesignSystem.Colors.primary)
                            Text(mode.rawValue)
                        }
                        .tag(mode)
                    }
                }
                
                if authMode == .usernamePassword {
                    ModernTextField(
                        title: "Username",
                        text: $username,
                        icon: "person",
                        placeholder: "Enter username"
                    )
                    
                    ModernTextField(
                        title: "Password",
                        text: $password,
                        icon: "lock",
                        placeholder: "Enter password",
                        isSecure: true
                    )
                }
                
                if authMode == .certificate || securityMode != .none {
                    certificateSection
                }
            }
        }
    }
    
    // MARK: - Advanced Settings Tab
    
    var advancedSettingsTab: some View {
        ModernForm {
            FormSection("Session") {
                ModernTextField(
                    title: "Application URI",
                    text: $applicationURI,
                    icon: "person.text.rectangle",
                    placeholder: "urn:vendor:application"
                )

                HStack(spacing: DesignSystem.Spacing.medium) {
                    ModernTextField(
                        title: "Requested Timeout (s)",
                        text: $requestedTimeout,
                        icon: "timer",
                        placeholder: "10"
                    )

                    ModernTextField(
                        title: "Session Timeout (s)",
                        text: $sessionTimeout,
                        icon: "clock",
                        placeholder: "60"
                    )
                }

                ModernTextField(
                    title: "Locale IDs",
                    text: $localeIDs,
                    icon: "globe",
                    placeholder: "en-US,de-DE"
                )
            }

            FormSection("Operational Policy") {
                ModernPicker("Keepalive Policy", selection: $keepalivePolicy, icon: "heart.text.square") {
                    ForEach(KeepalivePolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }

                ModernPicker("Reconnect Policy", selection: $reconnectPolicy, icon: "arrow.triangle.2.circlepath") {
                    ForEach(ReconnectPolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }

                ModernPicker("Trust Behavior", selection: $trustBehavior, icon: "checkmark.shield") {
                    ForEach(ProfileTrustBehavior.allCases) { behavior in
                        Text(behavior.rawValue).tag(behavior)
                    }
                }
            }

            FormSection("Classification") {
                ModernTextField(
                    title: "Tags",
                    text: $tags,
                    icon: "tag",
                    placeholder: "production,line-1,vendor"
                )

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                    HStack(spacing: DesignSystem.Spacing.xxSmall) {
                        Image(systemName: "note.text")
                            .foregroundColor(DesignSystem.Colors.primary)
                            .font(.system(size: 12, weight: .medium))
                        Text("NOTES")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }

                    TextEditor(text: $notes)
                        .font(DesignSystem.Typography.body)
                        .padding(DesignSystem.Spacing.small)
                        .frame(height: 90)
                        .background(Color.gray.opacity(0.06))
                        .cornerRadius(DesignSystem.CornerRadius.small)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                .stroke(DesignSystem.Colors.borderLight, lineWidth: 1)
                        )
                }
            }
        }
    }
    
    // MARK: - Certificate Section
    
    var certificateSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            filePickerField(
                title: "Client Certificate",
                path: $certificatePath,
                icon: "doc.badge.gearshape"
            )
            
            filePickerField(
                title: "Private Key",
                path: $privateKeyPath,
                icon: "key"
            )
            
            filePickerField(
                title: "Server Certificate",
                path: $serverCertificatePath,
                icon: "lock.doc"
            )
        }
    }
    
    func filePickerField(title: String, path: Binding<String>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
            HStack(spacing: DesignSystem.Spacing.xxSmall) {
                Image(systemName: icon)
                    .foregroundColor(DesignSystem.Colors.primary)
                    .font(.system(size: 12, weight: .medium))
                Text(title.uppercased())
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
            
            HStack {
                Text(path.wrappedValue.isEmpty ? "No file selected" : URL(fileURLWithPath: path.wrappedValue).lastPathComponent)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(path.wrappedValue.isEmpty ? DesignSystem.Colors.tertiaryText : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                Button("Browse...") {
                    selectFile(for: path, fileType: getFileType(for: title))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                if !path.wrappedValue.isEmpty {
                    Button(action: { path.wrappedValue = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DesignSystem.Spacing.small)
            .background(Color.gray.opacity(0.06))
            .cornerRadius(DesignSystem.CornerRadius.small)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .stroke(DesignSystem.Colors.borderLight, lineWidth: 1)
            )
        }
    }
    
    // MARK: - Connection Test Result View
    
    func connectionTestResultView(_ result: TestResult) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.success ? DesignSystem.Colors.success : DesignSystem.Colors.error)
                    .font(.system(size: 20))
                
                Text(result.message)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            if !result.hints.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                    ForEach(result.hints, id: \.self) { hint in
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.xSmall) {
                            Text("•")
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                            Text(hint)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                Text("CONNECTION REPORT")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                ForEach(result.report.steps) { step in
                    HStack(spacing: DesignSystem.Spacing.xSmall) {
                        Image(systemName: step.status.severity.systemImage)
                            .foregroundColor(step.status.severity.color)
                            .frame(width: 16)

                        Text(step.phase.rawValue)
                            .font(DesignSystem.Typography.caption)
                            .frame(width: 140, alignment: .leading)

                        Text(step.detail)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(1)

                        Spacer()

                        Text("\(step.durationMilliseconds) ms")
                            .font(DesignSystem.Typography.monospacedCaption)
                            .foregroundColor(DesignSystem.Colors.tertiaryText)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .background(result.success ? DesignSystem.Colors.success.opacity(0.1) : DesignSystem.Colors.error.opacity(0.1))
        .cornerRadius(DesignSystem.CornerRadius.small)
        .padding(.horizontal, DesignSystem.Spacing.large)
        .padding(.bottom, DesignSystem.Spacing.small)
    }
    
    // MARK: - Helper Functions
    
    func authModeIcon(_ mode: AuthenticationMode) -> String {
        switch mode {
        case .anonymous: return "person.crop.circle.badge.questionmark"
        case .usernamePassword: return "person.crop.circle.badge.checkmark"
        case .certificate: return "lock.doc"
        }
    }
    
    func loadServerData() {
        guard let server = server else { return }
        
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
        applicationURI = server.applicationURI
        requestedTimeout = String(format: "%.0f", server.requestedTimeout)
        sessionTimeout = String(format: "%.0f", server.sessionTimeout)
        localeIDs = server.localeIDs.joined(separator: ",")
        keepalivePolicy = server.keepalivePolicy
        reconnectPolicy = server.reconnectPolicy
        trustBehavior = server.trustBehavior
        tags = server.tags.joined(separator: ",")
        notes = server.notes
    }
    
    func saveServer() {
        let newServer = OPCUAServer(
            id: server?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            networkSchema: networkSchema,
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: Int(port) ?? networkSchema.defaultPort,
            securityMode: securityMode,
            securityPolicy: securityPolicy,
            authenticationMode: authMode,
            username: username.isEmpty ? nil : username,
            password: password.isEmpty ? nil : password,
            certificatePath: certificatePath.isEmpty ? nil : certificatePath,
            privateKeyPath: privateKeyPath.isEmpty ? nil : privateKeyPath,
            serverCertificatePath: serverCertificatePath.isEmpty ? nil : serverCertificatePath,
            description: serverDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            isDefault: server?.isDefault ?? false,
            applicationURI: applicationURI.trimmingCharacters(in: .whitespacesAndNewlines),
            requestedTimeout: Double(requestedTimeout) ?? 10,
            sessionTimeout: Double(sessionTimeout) ?? 60,
            localeIDs: splitCSV(localeIDs),
            keepalivePolicy: keepalivePolicy,
            reconnectPolicy: reconnectPolicy,
            trustBehavior: trustBehavior,
            tags: splitCSV(tags),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        if server == nil {
            appState.addServer(newServer)
        } else {
            appState.updateServer(newServer)
        }
        
        dismiss()
    }
    
    func testConnection() {
        isTesting = true
        testResult = nil
        
        // Create a test server configuration
        let testServer = OPCUAServer(
            id: UUID(),
            name: "Test Connection",
            networkSchema: networkSchema,
            host: host,
            port: Int(port) ?? networkSchema.defaultPort,
            securityMode: securityMode,
            securityPolicy: securityPolicy,
            authenticationMode: authMode,
            username: username.isEmpty ? nil : username,
            password: password.isEmpty ? nil : password,
            certificatePath: certificatePath.isEmpty ? nil : certificatePath,
            privateKeyPath: privateKeyPath.isEmpty ? nil : privateKeyPath,
            serverCertificatePath: serverCertificatePath.isEmpty ? nil : serverCertificatePath,
            applicationURI: applicationURI.trimmingCharacters(in: .whitespacesAndNewlines),
            requestedTimeout: Double(requestedTimeout) ?? 10,
            sessionTimeout: Double(sessionTimeout) ?? 60,
            localeIDs: splitCSV(localeIDs),
            keepalivePolicy: keepalivePolicy,
            reconnectPolicy: reconnectPolicy,
            trustBehavior: trustBehavior,
            tags: splitCSV(tags),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        Task {
            do {
                // Attempt to connect using the connection manager
                let connectionManager = appState.connectionManager
                let success = await connectionManager.connectToServer(testServer)
                
                await MainActor.run {
                    isTesting = false
                    
                    if success {
                        testResult = TestResult(
                            success: true,
                            message: "✅ Connection successful! Server is reachable and responding.",
                            hints: [],
                            report: ConnectionTestReportFactory.report(
                                for: testServer,
                                success: true,
                                detail: "Server is reachable and responding.",
                                hints: []
                            )
                        )
                        
                        // Clean up test connection
                        connectionManager.disconnectFromServer(testServer)
                    } else {
                        // Get detailed error information
                        let _ = connectionManager.getConnectionStatus(for: testServer)
                        let errorDetail = connectionManager.getLastError(for: testServer)
                        
                        var message = "❌ Connection failed."
                        var hints: [String] = []
                        
                        if let error = errorDetail {
                            message = "❌ \(error.message)"
                            hints = error.hints
                        } else {
                            // Provide general troubleshooting hints
                            hints = [
                                "Verify the server is running and accessible",
                                "Check that the endpoint URL is correct",
                                "Ensure firewall settings allow OPC UA traffic",
                                "Verify security settings match server configuration",
                                "Check username/password if authentication is required"
                            ]
                        }
                        
                        testResult = TestResult(
                            success: false,
                            message: message,
                            hints: hints,
                            report: ConnectionTestReportFactory.report(
                                for: testServer,
                                success: false,
                                detail: message,
                                hints: hints
                            )
                        )
                    }
                }
            }
        }
    }
    
    private func extractHost(from endpoint: String) -> String {
        // Extract host from opc.tcp://host:port format
        guard let url = URL(string: endpoint) else { return "localhost" }
        return url.host ?? "localhost"
    }
    
    private func extractPort(from endpoint: String) -> Int {
        // Extract port from opc.tcp://host:port format
        guard let url = URL(string: endpoint) else { return 4840 }
        return url.port ?? 4840
    }

    private func splitCSV(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private func getFileType(for title: String) -> [String] {
        if title.contains("Certificate") {
            return ["crt", "cer", "pem", "der"]
        } else if title.contains("Key") {
            return ["key", "pem", "der"]
        }
        return ["*"]
    }
    
    private func selectFile(for path: Binding<String>, fileType: [String]) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = fileType.map { UTType(filenameExtension: $0) }.compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                path.wrappedValue = url.path
            }
        }
        #endif
    }
}
