import SwiftUI
import SwiftData

@main
struct OpcUaClientApp: App {
    let modelContainer: ModelContainer?
    let startupErrorMessage: String?
    @StateObject private var appState: AppState

    init() {
        // Initialize SwiftData model container with all models
        let schema = Schema([
            ServerModel.self,
            SubscriptionModel.self,
            MonitoredItemModel.self
        ])
        let fileManager = FileManager.default
        let storeName = "OpcUaClient"

        let modelConfiguration = ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.modelContainer = container
            self.startupErrorMessage = nil

            // Initialize AppState with the model context
            let context = container.mainContext
            let state = AppState(modelContext: context)
            self._appState = StateObject(wrappedValue: state)
            print("✅ Successfully initialized SwiftData with persistent store")
        } catch {
            print("❌ Failed to create ModelContainer: \(error)")
            
            // Quarantine stores if it's a schema migration error or validation error
            let errorDescription = String(describing: error)
            if errorDescription.contains("migration") || 
               errorDescription.contains("incompatible") ||
               errorDescription.contains("Validation error") ||
               errorDescription.contains("134110") {
                print("🔄 Attempting to handle schema migration issue...")
                let bundleId = Bundle.main.bundleIdentifier ?? "twinedgeai.com.MacOpcUaClient"
                let appSupport = fileManager
                    .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                    .first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

                // SwiftData may place the store directly in Application Support for sandboxed builds,
                // while older builds used a bundle-id subfolder. Check both known locations.
                let storeDirectories = [
                    appSupport,
                    appSupport.appendingPathComponent(bundleId, isDirectory: true)
                ]

                Self.quarantineSwiftDataStoreFiles(
                    fileManager: fileManager,
                    storeName: storeName,
                    storeDirectories: storeDirectories
                )
                
                // Try to recreate with fresh store
                do {
                    let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                    self.modelContainer = container
                    self.startupErrorMessage = nil
                    let context = container.mainContext
                    let state = AppState(modelContext: context)
                    self._appState = StateObject(wrappedValue: state)
                    print("✅ Successfully recreated SwiftData store after migration")
                } catch {
                    // Fall back to in-memory store as last resort
                    print("⚠️ Falling back to in-memory SwiftData store: \(error)")
                    do {
                        let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                        let container = try ModelContainer(for: schema, configurations: [fallbackConfig])
                        self.modelContainer = container
                        self.startupErrorMessage = nil
                        let context = container.mainContext
                        let state = AppState(modelContext: context)
                        self._appState = StateObject(wrappedValue: state)
                    } catch {
                        self.modelContainer = nil
                        self.startupErrorMessage = "Failed to create in-memory SwiftData store after migration recovery: \(error)"
                        self._appState = StateObject(wrappedValue: AppState(modelContext: nil))
                    }
                }
            } else {
                // For other errors, just fall back to in-memory store without deleting
                print("⚠️ Falling back to in-memory SwiftData store: \(error)")
                do {
                    let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                    let container = try ModelContainer(for: schema, configurations: [fallbackConfig])
                    self.modelContainer = container
                    self.startupErrorMessage = nil
                    let context = container.mainContext
                    let state = AppState(modelContext: context)
                    self._appState = StateObject(wrappedValue: state)
                } catch {
                    self.modelContainer = nil
                    self.startupErrorMessage = "Failed to create in-memory SwiftData store: \(error)"
                    self._appState = StateObject(wrappedValue: AppState(modelContext: nil))
                }
            }
        }
    }

    private static func quarantineSwiftDataStoreFiles(
        fileManager: FileManager,
        storeName: String,
        storeDirectories: [URL]
    ) {
        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        for directory in storeDirectories {
            let quarantineDirectory = directory.appendingPathComponent(
                "\(storeName)-quarantine-\(timestamp)",
                isDirectory: true
            )
            var createdQuarantineDirectory = false

            for suffix in ["store", "store-shm", "store-wal"] {
                let storeURL = directory.appendingPathComponent("\(storeName).\(suffix)")
                guard fileManager.fileExists(atPath: storeURL.path) else {
                    continue
                }

                do {
                    if !createdQuarantineDirectory {
                        try fileManager.createDirectory(
                            at: quarantineDirectory,
                            withIntermediateDirectories: true
                        )
                        createdQuarantineDirectory = true
                    }

                    let destinationURL = quarantineDirectory.appendingPathComponent(storeURL.lastPathComponent)
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.removeItem(at: destinationURL)
                    }
                    try fileManager.moveItem(at: storeURL, to: destinationURL)
                    print("📦 Quarantined incompatible SwiftData store file at \(destinationURL.path)")
                } catch {
                    print("⚠️ Failed to quarantine SwiftData store file at \(storeURL.path): \(error)")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                ModernMainView()
                    .environmentObject(appState)
                    .environmentObject(appState.writeHistory)
                    .modelContainer(modelContainer)
                    .task {
                        await appState.loadInitialDataIfNeeded()
                        appState.runSubscriptionMigrations()
                    }
            } else {
                StartupFailureView(message: startupErrorMessage ?? "Failed to initialize application storage.")
            }
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            AppCommands(appState: appState)
        }
        #endif

        #if os(macOS)
        Settings {
            if let modelContainer {
                SettingsView()
                    .environmentObject(appState)
                    .environmentObject(appState.writeHistory)
                    .modelContainer(modelContainer)
            } else {
                StartupFailureView(message: startupErrorMessage ?? "Failed to initialize application storage.")
            }
        }
        #endif
    }
}

private struct StartupFailureView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storage Unavailable")
                .font(.title2)
                .fontWeight(.semibold)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 220, alignment: .center)
    }
}
