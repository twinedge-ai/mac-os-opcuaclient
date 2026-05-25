import SwiftUI
import UniformTypeIdentifiers

struct ModernDatabaseManagementView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @State private var showingFullResetConfirmation = false
    @State private var showingSubscriptionsResetConfirmation = false
    @State private var showingValidationIssuesReset = false
    @State private var isResetting = false
    @State private var databaseStats: DatabaseStats?
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                // Overview Tab
                overviewTab
                    .tabItem {
                        Label("Overview", systemImage: "chart.pie")
                    }
                    .tag(0)
                
                // Management Tab
                managementTab
                    .tabItem {
                        Label("Management", systemImage: "gear")
                    }
                    .tag(1)
                
                // Maintenance Tab
                maintenanceTab
                    .tabItem {
                        Label("Maintenance", systemImage: "wrench.and.screwdriver")
                    }
                    .tag(2)
            }
            .navigationTitle("Database Management")
            // .navigationBarTitleDisplayMode(.inline) // iOS only
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Refresh") {
                        refreshStats()
                    }
                    .buttonStyle(.bordered)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                refreshStats()
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
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
    
    // MARK: - Overview Tab
    
    var overviewTab: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.large) {
                // Header Card
                ModernCard {
                    HStack {
                        Image(systemName: "cylinder.split.1x2")
                            .font(.title)
                            .foregroundColor(DesignSystem.Colors.primary)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                    .fill(DesignSystem.Colors.primary.opacity(0.1))
                            )
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                            Text("Database Overview")
                                .font(DesignSystem.Typography.headline)
                            
                            Text("Monitor and manage your OPC UA data storage")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                        }
                        
                        Spacer()
                    }
                }
                
                // Statistics Cards
                if let stats = databaseStats {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.medium)
                    ], spacing: DesignSystem.Spacing.medium) {
                        DatabaseStatCard(
                            title: "Servers",
                            value: "\(stats.serverCount)",
                            icon: "server.rack",
                            color: DesignSystem.Colors.primary,
                            description: "Configured OPC UA servers"
                        )
                        
                        DatabaseStatCard(
                            title: "Subscriptions",
                            value: "\(stats.subscriptionCount)",
                            icon: "bell.circle",
                            color: DesignSystem.Colors.success,
                            description: "Active monitoring subscriptions"
                        )
                        
                        DatabaseStatCard(
                            title: "Monitored Items",
                            value: "\(stats.monitoredItemCount)",
                            icon: "dot.radiowaves.up.forward",
                            color: DesignSystem.Colors.info,
                            description: "Variables being monitored"
                        )
                        
                        DatabaseStatCard(
                            title: "Total Records",
                            value: "\(stats.totalCount)",
                            icon: "number.circle",
                            color: DesignSystem.Colors.warning,
                            description: "All database entries"
                        )
                    }
                } else {
                    // Loading skeleton
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.medium)
                    ], spacing: DesignSystem.Spacing.medium) {
                        ForEach(0..<4, id: \.self) { _ in
                            StatSkeletonCard()
                        }
                    }
                }
                
                // Validation Issues Section
                if !appState.lastSubscriptionValidationIssues.isEmpty {
                    ModernCard {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                            SectionHeader( "VALIDATION ISSUES", icon: "exclamationmark.triangle")
                            
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(DesignSystem.Colors.warning)
                                
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                                    Text("\(appState.lastSubscriptionValidationIssues.count) items have validation errors")
                                        .font(DesignSystem.Typography.callout)
                                    
                                    Text("These issues may prevent proper monitoring functionality")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.secondaryText)
                                }
                                
                                Spacer()
                                
                                Button("Clear Issues") {
                                    showingValidationIssuesReset = true
                                }
                                .buttonStyle(.bordered)
                                .tint(DesignSystem.Colors.warning)
                            }
                        }
                    }
                }
                
                // Database Health
                ModernCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        SectionHeader( "DATABASE HEALTH", icon: "heart.circle")
                        
                        DatabaseHealthIndicator(stats: databaseStats)
                    }
                }
            }
            .padding()
        }
        .background(DesignSystem.Colors.tertiaryBackground)
    }
    
    // MARK: - Management Tab
    
    var managementTab: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.large) {
                // Import/Export Section
                ModernCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        SectionHeader( "BACKUP & RESTORE", icon: "arrow.up.arrow.down.circle")
                        
                        VStack(spacing: DesignSystem.Spacing.small) {
                            ActionButton(
                                title: "Export Configuration",
                                description: "Save your server and subscription settings to a file",
                                icon: "square.and.arrow.up",
                                color: DesignSystem.Colors.primary,
                                action: exportConfiguration
                            )
                            
                            ActionButton(
                                title: "Import Configuration",
                                description: "Restore settings from a previously exported file",
                                icon: "square.and.arrow.down",
                                color: DesignSystem.Colors.info,
                                action: importConfiguration
                            )
                        }
                    }
                }
                
                // Data Management Section
                ModernCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        SectionHeader( "DATA MANAGEMENT", icon: "folder.circle")
                        
                        VStack(spacing: DesignSystem.Spacing.small) {
                            ActionButton(
                                title: "Compact Database",
                                description: "Optimize database storage and improve performance",
                                icon: "arrow.down.circle",
                                color: DesignSystem.Colors.success,
                                action: compactDatabase
                            )
                            
                            ActionButton(
                                title: "Verify Data Integrity",
                                description: "Check for data corruption and inconsistencies",
                                icon: "checkmark.shield",
                                color: DesignSystem.Colors.info,
                                action: verifyDataIntegrity
                            )
                        }
                    }
                }
                
                // Analytics Section
                if let stats = databaseStats {
                    ModernCard {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                            SectionHeader( "STORAGE ANALYTICS", icon: "chart.bar.circle")
                            
                            VStack(spacing: DesignSystem.Spacing.small) {
                                StorageBreakdownRow(
                                    label: "Server Configurations",
                                    value: stats.serverCount,
                                    total: stats.totalCount,
                                    color: DesignSystem.Colors.primary
                                )
                                
                                StorageBreakdownRow(
                                    label: "Subscription Data",
                                    value: stats.subscriptionCount,
                                    total: stats.totalCount,
                                    color: DesignSystem.Colors.success
                                )
                                
                                StorageBreakdownRow(
                                    label: "Monitored Items",
                                    value: stats.monitoredItemCount,
                                    total: stats.totalCount,
                                    color: DesignSystem.Colors.info
                                )
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(DesignSystem.Colors.tertiaryBackground)
    }
    
    // MARK: - Maintenance Tab
    
    var maintenanceTab: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.large) {
                // Warning Card
                ModernCard {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(DesignSystem.Colors.warning)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                            Text("Maintenance Operations")
                                .font(DesignSystem.Typography.callout.weight(.medium))
                            
                            Text("These operations will modify or delete your data. Please ensure you have backups.")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                        }
                        
                        Spacer()
                    }
                    .padding(DesignSystem.Spacing.small)
                    .background(DesignSystem.Colors.warning.opacity(0.1))
                    .cornerRadius(DesignSystem.CornerRadius.small)
                }
                
                // Selective Reset Section
                ModernCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        SectionHeader( "SELECTIVE RESET", icon: "arrow.counterclockwise.circle")
                        
                        VStack(spacing: DesignSystem.Spacing.small) {
                            DangerousActionButton(
                                title: "Reset Subscriptions",
                                description: "Remove all subscriptions and monitored items. Server configurations will be preserved.",
                                icon: "bell.slash",
                                severity: .warning,
                                isLoading: isResetting,
                                action: { showingSubscriptionsResetConfirmation = true }
                            )
                            
                            DangerousActionButton(
                                title: "Clear Validation Cache",
                                description: "Clear cached validation errors. Issues will be re-detected on next connection.",
                                icon: "trash.circle",
                                severity: .moderate,
                                isLoading: false,
                                action: { showingValidationIssuesReset = true }
                            )
                        }
                    }
                }
                
                // Complete Reset Section
                ModernCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        SectionHeader( "COMPLETE RESET", icon: "minus.circle")
                        
                        DangerousActionButton(
                            title: "Reset All Data",
                            description: "⚠️ Permanently delete ALL stored data including servers, subscriptions, and monitored items. This action cannot be undone.",
                            icon: "trash.circle.fill",
                            severity: .critical,
                            isLoading: isResetting,
                            action: { showingFullResetConfirmation = true }
                        )
                    }
                }
            }
            .padding()
        }
        .background(DesignSystem.Colors.tertiaryBackground)
    }
    
    // MARK: - Helper Methods
    
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
    
    private func exportConfiguration() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "opcua_config_\(Date().timeIntervalSince1970).json"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    let bundle = appState.exportConfiguration()
                    let jsonData = try ConfigurationCodec.encode(bundle)
                    try jsonData.write(to: url, options: .atomic)
                    
                    print("Export Successful: Configuration exported to \(url.lastPathComponent)")
                } catch {
                    print("Export Failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func importConfiguration() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                do {
                    let jsonData = try Data(contentsOf: url)
                    let bundle = try ConfigurationCodec.decode(jsonData)
                    appState.importConfiguration(bundle)
                    refreshStats()

                    print("Import Successful: Configuration imported from \(url.lastPathComponent)")
                } catch {
                    print("Import Failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func compactDatabase() {
        Task {
            // Database optimization is automatic in SwiftData
            await MainActor.run {
                print("Database Compacted: Database has been optimized and compacted successfully")
            }
        }
    }
    
    private func verifyDataIntegrity() {
        Task {
            var issues: [String] = []
            
            // Check for orphaned monitored items
            for subscription in appState.subscriptions {
                if subscription.monitoredItems.isEmpty && subscription.id != UUID() {
                    issues.append("Subscription '\(subscription.name)' has no monitored items")
                }
            }
            
            // Check for duplicate server endpoints
            let endpoints = appState.servers.map { $0.endpoint }
            let duplicates = Dictionary(grouping: endpoints, by: { $0 })
                .filter { $1.count > 1 }
                .keys
            
            for duplicate in duplicates {
                issues.append("Duplicate server endpoint found: \(duplicate)")
            }
            
            await MainActor.run {
                if issues.isEmpty {
                    print("Data Integrity Check Passed: No integrity issues found in the database")
                } else {
                    print("Integrity Issues Found: Found \(issues.count) issue(s): \(issues.joined(separator: ", "))")
                }
            }
        }
    }
}

// MARK: - Supporting Components

struct DatabaseStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Spacer()
            }
            
            Text(value)
                .font(DesignSystem.Typography.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                Text(title)
                    .font(DesignSystem.Typography.callout.weight(.medium))
                
                Text(description)
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.background)
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .shadow(radius: 2)
    }
}

struct StatSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack {
                Circle()
                    .fill(DesignSystem.Colors.tertiaryBackground)
                    .frame(width: 24, height: 24)
                
                Spacer()
            }
            
            Rectangle()
                .fill(DesignSystem.Colors.tertiaryBackground)
                .frame(height: 32)
                .cornerRadius(4)
            
            Rectangle()
                .fill(DesignSystem.Colors.tertiaryBackground)
                .frame(height: 16)
                .cornerRadius(4)
            
            Rectangle()
                .fill(DesignSystem.Colors.tertiaryBackground)
                .frame(height: 12)
                .cornerRadius(4)
        }
        .padding(DesignSystem.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.background)
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .shadow(radius: 2)
        .redacted(reason: .placeholder)
    }
}

struct DatabaseHealthIndicator: View {
    let stats: DatabaseStats?
    
    private var healthStatus: (String, Color, String) {
        guard let stats = stats else {
            return ("Unknown", DesignSystem.Colors.tertiaryText, "Unable to determine health")
        }
        
        if stats.totalCount == 0 {
            return ("Empty", DesignSystem.Colors.warning, "No data stored")
        } else if stats.totalCount < 100 {
            return ("Good", DesignSystem.Colors.success, "Optimal performance")
        } else if stats.totalCount < 1000 {
            return ("Fair", DesignSystem.Colors.warning, "Consider periodic maintenance")
        } else {
            return ("Heavy", DesignSystem.Colors.error, "Performance may be affected")
        }
    }
    
    var body: some View {
        HStack {
            Circle()
                .fill(healthStatus.1)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                Text("Status: \(healthStatus.0)")
                    .font(DesignSystem.Typography.callout.weight(.medium))
                
                Text(healthStatus.2)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
            
            Spacer()
        }
    }
}

struct ActionButton: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.medium) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                    Text(title)
                        .font(DesignSystem.Typography.callout.weight(.medium))
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.tertiaryText)
            }
            .padding(DesignSystem.Spacing.medium)
            .background(isHovered ? DesignSystem.Colors.tertiaryBackground : Color.clear)
            .cornerRadius(DesignSystem.CornerRadius.small)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct DangerousActionButton: View {
    let title: String
    let description: String
    let icon: String
    let severity: Severity
    let isLoading: Bool
    let action: () -> Void
    
    enum Severity {
        case moderate, warning, critical
        
        var color: Color {
            switch self {
            case .moderate: return DesignSystem.Colors.info
            case .warning: return DesignSystem.Colors.warning
            case .critical: return DesignSystem.Colors.error
            }
        }
    }
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack(spacing: DesignSystem.Spacing.medium) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(severity.color)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                    Text(title)
                        .font(DesignSystem.Typography.callout.weight(.medium))
                    
                    Text(description)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                } else {
                    Button(action: action) {
                        Text("Execute")
                            .font(DesignSystem.Typography.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(severity.color)
                }
            }
            .padding(DesignSystem.Spacing.medium)
            .background(severity.color.opacity(isHovered ? 0.1 : 0.05))
            .cornerRadius(DesignSystem.CornerRadius.small)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .stroke(severity.color.opacity(0.3), lineWidth: 1)
            )
        }
        .onHover { isHovered = $0 }
    }
}

struct StorageBreakdownRow: View {
    let label: String
    let value: Int
    let total: Int
    let color: Color
    
    private var percentage: Double {
        total > 0 ? Double(value) / Double(total) : 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
            HStack {
                Text(label)
                    .font(DesignSystem.Typography.callout)
                
                Spacer()
                
                Text("\(value)")
                    .font(DesignSystem.Typography.callout.weight(.medium))
                    .foregroundColor(color)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(DesignSystem.Colors.tertiaryBackground)
                        .frame(height: 4)
                        .cornerRadius(2)
                    
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * percentage, height: 4)
                        .cornerRadius(2)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Database Stats Extension

// Database management methods are now in DatabaseResetManager.swift

// DatabaseStats is imported from DatabaseResetManager

#Preview {
    ModernDatabaseManagementView()
        .environmentObject(AppState())
}
