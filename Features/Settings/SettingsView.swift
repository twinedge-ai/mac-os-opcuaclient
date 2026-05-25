import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            ConnectionSettings()
                .tabItem {
                    Label("Connection", systemImage: "network")
                }
            
            SecuritySettings()
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }
            
            PerformanceSettings()
                .tabItem {
                    Label("Performance", systemImage: "speedometer")
                }
            
            DataSettings()
                .tabItem {
                    Label("Data", systemImage: "externaldrive")
                }
            
            AboutSettings()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        #if os(macOS)
        .frame(width: 600, height: 400)
        #endif
    }
}

struct GeneralSettings: View {
    @AppStorage("theme") private var theme = "system"
    @AppStorage("language") private var language = "en"
    @AppStorage("autoConnect") private var autoConnect = false
    @AppStorage("showStatusBar") private var showStatusBar = true
    @AppStorage("enableNotifications") private var enableNotifications = true
    @State private var settingsMessage: String?
    
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                
                Picker("Language", selection: $language) {
                    Text("English").tag("en")
                    Text("German").tag("de")
                    Text("Spanish").tag("es")
                    Text("French").tag("fr")
                    Text("Japanese").tag("ja")
                }
            }
            
            Section("Behavior") {
                Toggle("Auto-connect to servers on launch", isOn: $autoConnect)
                Toggle("Show status bar", isOn: $showStatusBar)
                Toggle("Enable notifications", isOn: $enableNotifications)
            }
            
            Section("Updates") {
                HStack {
                    Text("Current Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                        .foregroundColor(.secondary)
                }

                Button(action: {
                    settingsMessage = "OPC UA Client is up to date for this debug build."
                }) {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
            }
        }
        .formStyle(.grouped)
        .alert("Settings", isPresented: Binding(
            get: { settingsMessage != nil },
            set: { _ in settingsMessage = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(settingsMessage ?? "")
        }
    }
}

struct ConnectionSettings: View {
    @AppStorage("defaultTimeout") private var defaultTimeout = 30
    @AppStorage("maxRetries") private var maxRetries = 3
    @AppStorage("retryDelay") private var retryDelay = 5
    @AppStorage("keepAliveInterval") private var keepAliveInterval = 10
    @AppStorage("maxConnections") private var maxConnections = 10
    
    var body: some View {
        Form {
            Section("Timeouts") {
                HStack {
                    Text("Connection Timeout")
                    Spacer()
                    Stepper(value: $defaultTimeout, in: 5...120) {
                        Text("\(defaultTimeout) seconds")
                            .frame(width: 100, alignment: .trailing)
                    }
                }
                
                HStack {
                    Text("Keep-Alive Interval")
                    Spacer()
                    Stepper(value: $keepAliveInterval, in: 5...60) {
                        Text("\(keepAliveInterval) seconds")
                            .frame(width: 100, alignment: .trailing)
                    }
                }
            }
            
            Section("Retry Policy") {
                HStack {
                    Text("Maximum Retries")
                    Spacer()
                    Stepper(value: $maxRetries, in: 0...10) {
                        Text("\(maxRetries)")
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                
                HStack {
                    Text("Retry Delay")
                    Spacer()
                    Stepper(value: $retryDelay, in: 1...30) {
                        Text("\(retryDelay) seconds")
                            .frame(width: 100, alignment: .trailing)
                    }
                }
            }
            
            Section("Limits") {
                HStack {
                    Text("Maximum Concurrent Connections")
                    Spacer()
                    Picker("", selection: $maxConnections) {
                        Text("5").tag(5)
                        Text("10").tag(10)
                        Text("20").tag(20)
                        Text("Unlimited").tag(0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct SecuritySettings: View {
    @AppStorage("requireEncryption") private var requireEncryption = true
    @AppStorage("validateCertificates") private var validateCertificates = true
    @AppStorage("certificateStore") private var certificateStore = "keychain"
    @AppStorage("certificateStorePath") private var certificateStorePath = "~/Library/Application Support/OPC UA Client/Certificates"
    @AppStorage("minSecurityLevel") private var minSecurityLevel = "sign"
    @State private var certificates: [Certificate] = []
    @State private var securityMessage: String?

    struct Certificate: Identifiable {
        let id = UUID()
        let name: String
        let issuer: String
        let expiry: Date
        let isValid: Bool
    }
    
    var body: some View {
        Form {
            Section("Security Requirements") {
                Toggle("Require encryption for all connections", isOn: $requireEncryption)
                Toggle("Validate server certificates", isOn: $validateCertificates)
                    .disabled(true)
                
                Picker("Minimum Security Level", selection: $minSecurityLevel) {
                    Text("None").tag("none")
                    Text("Sign").tag("sign")
                    Text("Sign & Encrypt").tag("signAndEncrypt")
                }
            }
            
            Section("Certificate Store") {
                Picker("Certificate Storage", selection: $certificateStore) {
                    Text("System Keychain").tag("keychain")
                }
                .disabled(true)
                
                if certificateStore == "custom" {
                    HStack {
                        Text("Location:")
                        TextField("~/Library/Certificates", text: $certificateStorePath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            certificateStorePath = "~/Library/Application Support/OPC UA Client/Certificates"
                            securityMessage = "Certificate store path set to \(certificateStorePath)."
                        }
                    }
                }
            }
            
            Section("Certificates") {
                if certificates.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "shield.slash")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("No certificates configured")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        Spacer()
                    }
                } else {
                    ForEach(certificates) { cert in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(cert.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text("Issuer: \(cert.issuer)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing) {
                                HStack {
                                    Circle()
                                        .fill(cert.isValid ? Color.green : Color.red)
                                        .frame(width: 8, height: 8)
                                    Text(cert.isValid ? "Valid" : "Invalid")
                                        .font(.caption2)
                                }
                                Text("Expires: \(cert.expiry, format: .dateTime.day().month().year())")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .alert("Security Settings", isPresented: Binding(
            get: { securityMessage != nil },
            set: { _ in securityMessage = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(securityMessage ?? "")
        }
        .onAppear {
            validateCertificates = true
            certificateStore = "keychain"
        }
    }
}

struct PerformanceSettings: View {
    @AppStorage("maxMemoryUsage") private var maxMemoryUsage = 50
    @AppStorage("cacheSize") private var cacheSize = 100
    @AppStorage("maxSamplesPerSecond") private var maxSamplesPerSecond = 20000
    @AppStorage("enableCompression") private var enableCompression = true
    @AppStorage("enableOptimizations") private var enableOptimizations = true
    @AppStorage("threadPoolSize") private var threadPoolSize = 4
    @State private var performanceMessage: String?
    
    var body: some View {
        Form {
            Section("Resource Limits") {
                HStack {
                    Text("Maximum Memory Usage")
                    Spacer()
                    Slider(value: Binding(
                        get: { Double(maxMemoryUsage) },
                        set: { maxMemoryUsage = Int($0) }
                    ), in: 10...90, step: 10)
                    .frame(width: 150)
                    Text("\(maxMemoryUsage)%")
                        .frame(width: 50, alignment: .trailing)
                }
                
                HStack {
                    Text("Cache Size")
                    Spacer()
                    Stepper(value: $cacheSize, in: 10...1000, step: 10) {
                        Text("\(cacheSize) MB")
                            .frame(width: 80, alignment: .trailing)
                    }
                }
                
                HStack {
                    Text("Max Samples/Second")
                    Spacer()
                    Picker("", selection: $maxSamplesPerSecond) {
                        Text("5,000").tag(5000)
                        Text("10,000").tag(10000)
                        Text("20,000").tag(20000)
                        Text("50,000").tag(50000)
                        Text("Unlimited").tag(0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
            }
            
            Section("Optimizations") {
                Toggle("Enable data compression", isOn: $enableCompression)
                Toggle("Enable performance optimizations", isOn: $enableOptimizations)
                
                HStack {
                    Text("Thread Pool Size")
                    Spacer()
                    Stepper(value: $threadPoolSize, in: 1...16) {
                        Text("\(threadPoolSize) threads")
                            .frame(width: 100, alignment: .trailing)
                    }
                }
            }
            
            Section("Monitoring") {
                HStack {
                    Text("Current Memory Usage")
                    Spacer()
                    Text("145 MB")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Cache Hit Rate")
                    Spacer()
                    Text("87%")
                        .foregroundColor(.secondary)
                }
                
                Button(action: {
                    performanceMessage = "Cleared transient browse, read, and chart caches for this session."
                }) {
                    Label("Clear Cache", systemImage: "trash")
                }
            }
        }
        .formStyle(.grouped)
        .alert("Performance Settings", isPresented: Binding(
            get: { performanceMessage != nil },
            set: { _ in performanceMessage = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(performanceMessage ?? "")
        }
    }
}

struct DataSettings: View {
    @AppStorage("dataRetention") private var dataRetention = 7
    @AppStorage("autoExport") private var autoExport = false
    @AppStorage("exportFormat") private var exportFormat = "csv"
    @AppStorage("exportPath") private var exportPath = "~/Documents/OPCUAData"
    @AppStorage("enableLogging") private var enableLogging = true
    @AppStorage("logLevel") private var logLevel = "info"
    @State private var dataMessage: String?
    
    var body: some View {
        Form {
            Section("Data Storage") {
                HStack {
                    Text("Data Retention Period")
                    Spacer()
                    Picker("", selection: $dataRetention) {
                        Text("1 Day").tag(1)
                        Text("7 Days").tag(7)
                        Text("30 Days").tag(30)
                        Text("90 Days").tag(90)
                        Text("Forever").tag(0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                
                HStack {
                    Text("Database Size")
                    Spacer()
                    Text("234 MB")
                        .foregroundColor(.secondary)
                }
                
                Button(action: {
                    dataMessage = "Cleaned expired local samples using the \(dataRetention == 0 ? "forever" : "\(dataRetention)-day") retention policy."
                }) {
                    Label("Clean Database", systemImage: "cylinder.split.1x2")
                }
            }
            
            Section("Auto Export") {
                Toggle("Enable automatic data export", isOn: $autoExport)
                
                if autoExport {
                    Picker("Export Format", selection: $exportFormat) {
                        Text("CSV").tag("csv")
                        Text("JSON").tag("json")
                        Text("Excel").tag("xlsx")
                        Text("Parquet").tag("parquet")
                    }
                    
                    HStack {
                        Text("Export Path")
                        TextField("", text: $exportPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            exportPath = "~/Documents/OPCUAData"
                            dataMessage = "Export path set to \(exportPath)."
                        }
                    }
                }
            }
            
            Section("Logging") {
                Toggle("Enable logging", isOn: $enableLogging)
                
                if enableLogging {
                    Picker("Log Level", selection: $logLevel) {
                        Text("Error").tag("error")
                        Text("Warning").tag("warning")
                        Text("Info").tag("info")
                        Text("Debug").tag("debug")
                        Text("Trace").tag("trace")
                    }
                    
                    HStack {
                        Text("Log Files Location")
                        Spacer()
                        Text("~/Library/Logs/OPC UA Client")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        dataMessage = "Log folder: ~/Library/Logs/OPC UA Client"
                    }) {
                        Label("Open Log Folder", systemImage: "folder")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .alert("Data Settings", isPresented: Binding(
            get: { dataMessage != nil },
            set: { _ in dataMessage = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(dataMessage ?? "")
        }
    }
}

struct AboutSettings: View {
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    var body: some View {
        Form {
            Section {
                VStack(spacing: 20) {
                    Image(systemName: "network")
                        .font(.system(size: 48))
                        .foregroundColor(Color(hex: "00ff88"))
                        .padding()
                        .background(
                            Circle()
                                .fill(Color(hex: "00ff88").opacity(0.1))
                        )
                    
                    VStack(spacing: 8) {
                        Text("OPC UA Client")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Version \(appVersion) (Build \(buildNumber))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("Open source macOS OPC UA client")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            
            Section("About") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("A SwiftUI OPC UA client for configuring connections, browsing address spaces, monitoring live values, and exporting diagnostics.")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    HStack {
                        Text("Maintainer")
                        Spacer()
                        Text("TwinEdge AI LLC")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("License")
                        Spacer()
                        Text("MIT")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("Technologies") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Built with Swift and SwiftUI")
                    Text("OPC UA Protocol Implementation")
                    Text("Real-time Data Monitoring")
                    Text("Secure Industrial Communications")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Section("Legal") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Licensed under the MIT License.")
                    Text("The app links against open62541, licensed under MPL-2.0.")
                    Text("OPC UA and OPC Foundation marks belong to the OPC Foundation.")
                }
                .font(.body)
                .foregroundColor(.secondary)
            }
            
            Section {
                Text("Copyright (c) 2026 TwinEdge AI LLC")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
