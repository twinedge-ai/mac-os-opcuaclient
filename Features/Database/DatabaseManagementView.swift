import SwiftUI

/// View for managing database operations including reset
struct DatabaseManagementView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingFullResetConfirmation = false
    @State private var showingSubscriptionsResetConfirmation = false
    @State private var showingValidationIssuesReset = false
    @State private var isResetting = false
    @State private var databaseStats: DatabaseStats?
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                
                Text("Database Management")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Manage your stored servers, subscriptions, and monitored items")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Current Database Stats
            if let stats = databaseStats {
                GroupBox("Current Database Contents") {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "server.rack")
                            Text("Servers:")
                            Spacer()
                            Text("\(stats.serverCount)")
                                .fontWeight(.semibold)
                        }
                        
                        HStack {
                            Image(systemName: "bell.circle")
                            Text("Subscriptions:")
                            Spacer()
                            Text("\(stats.subscriptionCount)")
                                .fontWeight(.semibold)
                        }
                        
                        HStack {
                            Image(systemName: "dot.radiowaves.up.forward")
                            Text("Monitored Items:")
                            Spacer()
                            Text("\(stats.monitoredItemCount)")
                                .fontWeight(.semibold)
                        }
                        
                        Divider()
                        
                        HStack {
                            Text("Total Records:")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(stats.totalCount)")
                                .fontWeight(.bold)
                        }
                    }
                }
                .padding()
            }
            
            // Validation Issues
            if !appState.lastSubscriptionValidationIssues.isEmpty {
                GroupBox("Validation Issues") {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("\(appState.lastSubscriptionValidationIssues.count) items have validation errors")
                            Spacer()
                        }
                        
                        Button("Clear Validation Issues") {
                            showingValidationIssuesReset = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            
            // Reset Options
            GroupBox("Reset Options") {
                VStack(spacing: 12) {
                    // Reset Subscriptions Only
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Button(action: { showingSubscriptionsResetConfirmation = true }) {
                                Label("Reset Subscriptions", systemImage: "bell.slash")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isResetting)
                            
                            Spacer()
                        }
                        
                        Text("Removes all subscriptions and monitored items. Keeps server configurations.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // Full Database Reset
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Button(action: { showingFullResetConfirmation = true }) {
                                Label("Reset All Data", systemImage: "trash.circle")
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.red)
                            .disabled(isResetting)
                            
                            Spacer()
                        }
                        
                        Text("⚠️ Completely removes all stored data including servers, subscriptions, and monitored items. Cannot be undone.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
            
            // Refresh button
            Button("Refresh Statistics") {
                refreshStats()
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
        .padding()
        .onAppear {
            refreshStats()
        }
        // Full reset confirmation
        .confirmationDialog(
            "Reset All Data",
            isPresented: $showingFullResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All Data", role: .destructive) {
                performFullReset()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete ALL stored data including servers, subscriptions, and monitored items. This action cannot be undone.")
        }
        // Subscriptions reset confirmation
        .confirmationDialog(
            "Reset Subscriptions",
            isPresented: $showingSubscriptionsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Subscriptions", role: .destructive) {
                performSubscriptionsReset()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete all subscriptions and monitored items, but keep your server configurations.")
        }
        // Validation issues reset
        .confirmationDialog(
            "Clear Validation Issues",
            isPresented: $showingValidationIssuesReset,
            titleVisibility: .visible
        ) {
            Button("Clear Issues") {
                appState.lastSubscriptionValidationIssues.removeAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will clear the validation error cache. Issues will be detected again on next connection.")
        }
    }
    
    private func refreshStats() {
        databaseStats = appState.getDatabaseStats()
    }
    
    private func performFullReset() {
        isResetting = true
        Task {
            await appState.resetDatabase()
            await MainActor.run {
                isResetting = false
                refreshStats()
            }
        }
    }
    
    private func performSubscriptionsReset() {
        isResetting = true
        Task {
            await appState.resetSubscriptions()
            await MainActor.run {
                isResetting = false
                refreshStats()
            }
        }
    }
}

#Preview {
    DatabaseManagementView()
        .environmentObject(AppState())
}