import SwiftUI
import UniformTypeIdentifiers

// Placeholder views for components not yet created
struct EnhancedServerConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Enhanced Server Configuration")
                    .font(.title)
                Text("Coming Soon")
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Server Configuration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct ConnectionProfilesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @StateObject private var profileManager = ConnectionProfileManager.shared
    @State private var showingCreateProfile = false
    @State private var showingImport = false
    @State private var showingExport = false
    @State private var exportDocument: JSONDocument?
    
    var body: some View {
        NavigationView {
            List {
                Section("Profiles") {
                    if profileManager.profiles.isEmpty {
                        Text("No profiles saved yet.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(profileManager.profiles) { profile in
                            ProfileRow(profile: profile)
                                .contextMenu {
                                    Button(profile.isFavorite ? "Unfavorite" : "Favorite") {
                                        profileManager.toggleFavorite(for: profile)
                                    }
                                    Button("Export Profile") {
                                        exportDocument = JSONDocument(data: (try? profileManager.exportProfile(profile)) ?? Data())
                                        showingExport = true
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        profileManager.deleteProfile(profile)
                                    }
                                }
                        }
                    }
                }
                
                Section("Quick Connect Templates") {
                    ForEach(profileManager.quickConnectTemplates) { template in
                        HStack {
                            Image(systemName: template.icon)
                                .foregroundColor(template.category.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                Text(template.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(template.defaultSecurityMode.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Connection Profiles")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Create Profile") { showingCreateProfile = true }
                        Button("Import Profiles") { showingImport = true }
                        Button("Export All Profiles") {
                            exportDocument = JSONDocument(data: (try? profileManager.exportAllProfiles()) ?? Data())
                            showingExport = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingCreateProfile) {
                CreateProfileView()
                    .environmentObject(appState)
            }
            .fileImporter(
                isPresented: $showingImport,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    if let data = try? Data(contentsOf: url) {
                        try? profileManager.importProfiles(from: data, replace: false)
                    }
                case .failure:
                    break
                }
            }
            .fileExporter(
                isPresented: $showingExport,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "opcua_profiles"
            ) { _ in }
        }
    }
}

private struct ProfileRow: View {
    let profile: ConnectionProfileManager.ConnectionProfile
    
    var body: some View {
        HStack {
            Image(systemName: profile.icon)
                .foregroundColor(colorFromName(profile.color))
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                Text("\(profile.server.name) • \(profile.category.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if profile.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
            }
        }
    }

    private func colorFromName(_ name: String) -> Color {
        switch name.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "brown": return .brown
        case "gray", "grey": return .gray
        default: return .blue
        }
    }
}

private struct CreateProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @StateObject private var profileManager = ConnectionProfileManager.shared
    @State private var selectedServerId: UUID?
    @State private var profileName = ""
    @State private var category: OPCUAServer.ProfileCategory = .development
    
    var selectedServer: OPCUAServer? {
        appState.servers.first { $0.id == selectedServerId }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Profile") {
                    LabeledContent("Name") {
                        TextField("Profile Name", text: $profileName)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Category") {
                        Picker("", selection: $category) {
                            ForEach(OPCUAServer.ProfileCategory.allCases, id: \.self) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
                
                Section("Server") {
                    Picker("Server", selection: $selectedServerId) {
                        Text("Select a server").tag(Optional<UUID>.none)
                        ForEach(appState.servers) { server in
                            Text(server.name).tag(Optional(server.id))
                        }
                    }
                }
            }
            .navigationTitle("New Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveProfile() }
                        .disabled(selectedServer == nil)
                }
            }
            .onAppear {
                if selectedServerId == nil {
                    selectedServerId = appState.servers.first?.id
                }
                if profileName.isEmpty, let server = selectedServer {
                    profileName = server.name
                }
            }
        }
    }
    
    private func saveProfile() {
        guard let server = selectedServer else { return }
        let profile = profileManager.createProfile(from: server, name: profileName.isEmpty ? server.name : profileName)
        var updated = profile
        updated.category = category
        profileManager.updateProfile(updated)
        dismiss()
    }
}

private struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    
    init(data: Data = Data()) {
        self.data = data
    }
    
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
