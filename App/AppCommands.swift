import SwiftUI

struct AppCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Connection Profile") {
                appState.showingServerConnection = true
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("Import Configuration...") {
                appState.selectedTab = .servers
            }

            Button("Export Configuration...") {
                appState.selectedTab = .reports
            }
            .keyboardShortcut("e", modifiers: .command)

            Button("Export Diagnostics Bundle...") {
                appState.selectedTab = .diagnostics
            }

            Divider()

            Button("Database Management...") {
                appState.showingDatabaseManagement = true
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }

        CommandMenu("Connection") {
            Button("Connect") {
                appState.showingServerConnection = true
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("Disconnect") {
                appState.connectionManager.disconnectAll()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(appState.servers.allSatisfy { !appState.connectionManager.isConnected(to: $0) })

            Button("Reconnect") {
                appState.showingServerConnection = true
            }

            Button("Discover Endpoints") {
                appState.selectedTab = .servers
            }

            Button("Trust Server Certificate...") {
                appState.selectedTab = .security
            }
        }

        CommandMenu("Node") {
            Button("Read") {
                appState.selectedTab = .browse
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Write...") {
                appState.selectedTab = .readWrite
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])

            Button("Subscribe") {
                appState.selectedTab = .subscriptions
            }

            Divider()

            Button("Copy NodeId") { }
            Button("Copy Browse Path") { }
        }

        CommandMenu("Subscription") {
            Button("Create Subscription...") {
                appState.selectedTab = .subscriptions
            }

            Button("Pause Publishing") {
                appState.selectedTab = .subscriptions
            }

            Button("Resume Publishing") {
                appState.selectedTab = .subscriptions
            }

            Button("Modify Parameters...") {
                appState.selectedTab = .subscriptions
            }
        }

        CommandMenu("Security") {
            Button("Application Certificate") {
                appState.selectedTab = .security
            }

            Button("Trusted Certificates") {
                appState.selectedTab = .security
            }

            Button("Rejected Certificates") {
                appState.selectedTab = .security
            }
        }

        CommandGroup(after: .sidebar) {
            Button("Show Inspector") {
                appState.selectedTab = .browse
            }

            Button("Show Raw Details") {
                appState.selectedTab = .diagnostics
            }

            Button("Customize Columns...") { }
        }
    }
}
