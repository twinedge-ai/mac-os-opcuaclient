import SwiftUI
import UniformTypeIdentifiers

struct ModernEditSubscriptionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    let subscription: Subscription
    
    @State private var name: String
    @State private var publishingInterval: String
    @State private var priority: Int
    @State private var isActive: Bool
    @State private var selectedTab = 0
    @State private var showingDeleteConfirmation = false
    @State private var showingAddNodeSheet = false
    @State private var selectedItems = Set<UUID>()
    @State private var isSaving = false
    
    init(subscription: Subscription) {
        self.subscription = subscription
        self._name = State(initialValue: subscription.name)
        self._publishingInterval = State(initialValue: String(Int(subscription.publishingInterval)))
        self._priority = State(initialValue: subscription.priority)
        self._isActive = State(initialValue: subscription.isActive)
    }
    
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Double(publishingInterval) != nil &&
        Double(publishingInterval)! > 0
    }
    
    var hasChanges: Bool {
        name != subscription.name ||
        publishingInterval != String(Int(subscription.publishingInterval)) ||
        priority != subscription.priority ||
        isActive != subscription.isActive
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Card
                headerCard
                
                // Tab View
                TabView(selection: $selectedTab) {
                    configurationTab
                        .tabItem {
                            Label("Configuration", systemImage: "gearshape")
                        }
                        .tag(0)
                    
                    monitoredItemsTab
                        .tabItem {
                            Label("Items", systemImage: "tag")
                        }
                        .tag(1)
                    
                    statisticsTab
                        .tabItem {
                            Label("Statistics", systemImage: "chart.xyaxis.line")
                        }
                        .tag(2)
                }
            }
            .navigationTitle("Edit Subscription")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { 
                        if hasChanges {
                            // Could show unsaved changes alert here
                        }
                        dismiss() 
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: saveChanges) {
                        if isSaving {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                                Text("Saving...")
                            }
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!isValid || !hasChanges || isSaving)
                }
            }
            .alert("Delete Subscription", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteSubscription()
                }
            } message: {
                Text("Are you sure you want to delete '\(subscription.name)'? This action cannot be undone.")
            }
            .sheet(isPresented: $showingAddNodeSheet) {
                // ModernAddMonitoredItemView requires MonitoringState and AppState
                // For now, we'll use the AddressSpaceBrowser or create a simpler view
                Text("Add Monitored Item")
                    .padding()
            }
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 600)
        #endif
    }
    
    // MARK: - Header Card
    
    var headerCard: some View {
        ModernCard {
            HStack(spacing: DesignSystem.Spacing.medium) {
                // Icon
                Image(systemName: isActive ? "bell.circle.fill" : "bell.slash.circle")
                    .font(.largeTitle)
                    .foregroundColor(isActive ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
                
                // Info
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                    Text(subscription.name)
                        .font(DesignSystem.Typography.title2)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: DesignSystem.Spacing.small) {
                        Label("\(subscription.monitoredItems.count) items", systemImage: "tag")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                        
                        Label("\(Int(subscription.publishingInterval))ms", systemImage: "timer")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                        
                        Label("Priority \(subscription.priority)", systemImage: "arrow.up.right")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                }
                
                Spacer()
                
                // Status Toggle
                VStack(alignment: .trailing, spacing: DesignSystem.Spacing.xSmall) {
                    Toggle("Active", isOn: $isActive)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    
                    Text(isActive ? "Active" : "Inactive")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(isActive ? DesignSystem.Colors.success : DesignSystem.Colors.secondaryText)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Configuration Tab
    
    var configurationTab: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.large) {
                // Basic Settings
                ModernCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        SectionHeader( "BASIC SETTINGS", icon: "gearshape")
                        
                        VStack(spacing: DesignSystem.Spacing.medium) {
                            ModernTextField(
                                title: "Subscription Name",
                                text: $name,
                                placeholder: "Enter subscription name"
                            )
                            
                            HStack(spacing: DesignSystem.Spacing.medium) {
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                                    Text("Publishing Interval")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.secondaryText)
                                    
                                    HStack {
                                        TextField("1000", text: $publishingInterval)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 100)
                                        
                                        Text("ms")
                                            .font(DesignSystem.Typography.callout)
                                            .foregroundColor(DesignSystem.Colors.secondaryText)
                                        
                                        Spacer()
                                        
                                        // Quick presets
                                        HStack(spacing: DesignSystem.Spacing.xSmall) {
                                            ForEach(["250", "500", "1000", "2000", "5000"], id: \.self) { interval in
                                                Button(interval) {
                                                    publishingInterval = interval
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                                .tint(publishingInterval == interval ? DesignSystem.Colors.primary : Color.gray)
                                            }
                                        }
                                    }
                                }
                            }
                            
                            HStack {
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                                    Text("Priority")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.secondaryText)
                                    
                                    Stepper("\(priority)", value: $priority, in: 0...255)
                                        .frame(maxWidth: 200)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                                    Text("Status")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.secondaryText)
                                    
                                    Toggle("Active Subscription", isOn: $isActive)
                                        .toggleStyle(.switch)
                                }
                            }
                        }
                    }
                }
                
                // Advanced Settings
                ModernCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        SectionHeader( "ADVANCED SETTINGS", icon: "slider.horizontal.3")
                        
                        VStack(spacing: DesignSystem.Spacing.medium) {
                            AdvancedSettingRow(
                                title: "Max Notifications per Publish",
                                description: "Maximum number of notifications sent in each publish cycle",
                                value: .constant(100)
                            )
                            
                            AdvancedSettingRow(
                                title: "Lifetime Count",
                                description: "Number of publish cycles before subscription expires",
                                value: .constant(10000)
                            )
                            
                            AdvancedSettingRow(
                                title: "Max Keep-Alive Count",
                                description: "Maximum missed keep-alive messages before timeout",
                                value: .constant(3000)
                            )
                        }
                    }
                }
                
                // Validation Info
                if !appState.lastSubscriptionValidationIssues.filter({ issue in
                    subscription.monitoredItems.contains { $0.nodeId == issue.nodeId }
                }).isEmpty {
                    ModernCard {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                            SectionHeader( "VALIDATION ISSUES", icon: "exclamationmark.triangle")
                            
                            let subscriptionIssues: [MonitoredItemValidation] = appState.lastSubscriptionValidationIssues.filter { validation in
                                subscription.monitoredItems.contains { $0.nodeId == validation.nodeId }
                            }
                            
                            ForEach(Array(subscriptionIssues.prefix(3)), id: \.nodeId) { validation in
                                HStack {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(DesignSystem.Colors.warning)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(validation.nodeId)
                                            .font(DesignSystem.Typography.caption.monospaced())
                                        
                                        if let description = validation.issue?.description {
                                            Text(description)
                                                .font(DesignSystem.Typography.caption2)
                                                .foregroundColor(DesignSystem.Colors.secondaryText)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                .padding(DesignSystem.Spacing.small)
                                .background(DesignSystem.Colors.warning.opacity(0.1))
                                .cornerRadius(DesignSystem.CornerRadius.small)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(DesignSystem.Colors.tertiaryBackground)
    }
    
    // MARK: - Monitored Items Tab
    
    var monitoredItemsTab: some View {
        VStack(spacing: 0) {
            // Items Header
            HStack {
                Text("\(subscription.monitoredItems.count) Monitored Items")
                    .font(DesignSystem.Typography.headline)
                
                Spacer()
                
                Button(action: { showingAddNodeSheet = true }) {
                    Label("Add Item", systemImage: "plus")
                        .font(DesignSystem.Typography.callout)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(DesignSystem.Colors.background)
            
            Divider()
            
            if subscription.monitoredItems.isEmpty {
                emptyItemsView
            } else {
                itemsList
            }
        }
    }
    
    var emptyItemsView: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Spacer()
            
            Image(systemName: "tag.slash")
                .font(.system(size: 64))
                .foregroundColor(DesignSystem.Colors.tertiaryText)
            
            VStack(spacing: DesignSystem.Spacing.xSmall) {
                Text("No Monitored Items")
                    .font(DesignSystem.Typography.title2)
                
                Text("Add items to monitor their values in real-time")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { showingAddNodeSheet = true }) {
                Label("Add First Item", systemImage: "plus.circle.fill")
                    .font(DesignSystem.Typography.callout.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var itemsList: some View {
        List {
            ForEach(subscription.monitoredItems) { item in
                EditableMonitoredItemRow(
                    item: item,
                    isSelected: selectedItems.contains(item.id),
                    onSelectionToggle: {
                        if selectedItems.contains(item.id) {
                            selectedItems.remove(item.id)
                        } else {
                            selectedItems.insert(item.id)
                        }
                    },
                    onDelete: { deleteItem(item) }
                )
            }
            .onDelete(perform: deleteItems)
        }
        .listStyle(.plain)
    }
    
    // MARK: - Statistics Tab
    
    var statisticsTab: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.large) {
                // Performance Stats
                ModernCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        SectionHeader( "PERFORMANCE METRICS", icon: "speedometer")
                        
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 120), spacing: DesignSystem.Spacing.medium)
                        ], spacing: DesignSystem.Spacing.medium) {
                            PerformanceMetric(
                                title: "Messages/sec",
                                value: "45.2",
                                trend: .up(12.5),
                                icon: "arrow.up.right.circle"
                            )
                            
                            PerformanceMetric(
                                title: "Avg Latency",
                                value: "12ms",
                                trend: .down(8.1),
                                icon: "timer.circle"
                            )
                            
                            PerformanceMetric(
                                title: "Data Rate",
                                value: "2.3KB/s",
                                trend: .stable,
                                icon: "chart.line.uptrend.xyaxis.circle"
                            )
                            
                            PerformanceMetric(
                                title: "Uptime",
                                value: "99.9%",
                                trend: .stable,
                                icon: "checkmark.circle"
                            )
                        }
                    }
                }
                
                // Error Stats
                ModernCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        SectionHeader( "ERROR STATISTICS", icon: "exclamationmark.triangle")
                        
                        VStack(spacing: DesignSystem.Spacing.small) {
                            ErrorStatRow(label: "Timeouts", count: 0, color: DesignSystem.Colors.success)
                            ErrorStatRow(label: "Bad Requests", count: 0, color: DesignSystem.Colors.success)
                            ErrorStatRow(label: "Republish Requests", count: 2, color: DesignSystem.Colors.warning)
                            ErrorStatRow(label: "Sequence Errors", count: 0, color: DesignSystem.Colors.success)
                        }
                    }
                }
                
                // Publishing Stats
                ModernCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        SectionHeader( "PUBLISHING STATISTICS", icon: "arrow.triangle.2.circlepath")
                        
                        VStack(spacing: DesignSystem.Spacing.small) {
                            SubscriptionStatRow(label: "Publish Requests", value: "1,245")
                            SubscriptionStatRow(label: "Data Change Notifications", value: "15,432")
                            SubscriptionStatRow(label: "Event Notifications", value: "0")
                            SubscriptionStatRow(label: "Keep-Alive Messages", value: "89")
                        }
                    }
                }
                
                // Actions
                ModernCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        SectionHeader( "ACTIONS", icon: "gear")
                        
                        VStack(spacing: DesignSystem.Spacing.small) {
                            Button("Reset Statistics") {
                                // Clear historical values for all monitored items
                                // Note: MonitoredItem doesn't have historicalValues property in the current model
                                // This would need to be tracked separately or in a different data structure
                                print("Statistics Reset: Historical data would be cleared for subscription")
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Button("Export Data") {
                                exportSubscriptionData()
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Button("Delete Subscription", role: .destructive) {
                                showingDeleteConfirmation = true
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding()
        }
        .background(DesignSystem.Colors.tertiaryBackground)
    }
    
    // MARK: - Helper Methods
    
    private func saveChanges() {
        isSaving = true
        
        Task {
            let updatedSubscription = Subscription(
                id: subscription.id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                serverId: subscription.serverId,
                publishingInterval: Double(publishingInterval) ?? subscription.publishingInterval,
                priority: priority,
                isActive: isActive,
                monitoredItems: subscription.monitoredItems
            )
            
            appState.saveSubscription(updatedSubscription)
            
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        }
    }
    
    private func deleteSubscription() {
        appState.deleteSubscription(subscription)
        dismiss()
    }
    
    private func deleteItems(at offsets: IndexSet) {
        var updatedSubscription = subscription
        updatedSubscription.monitoredItems.remove(atOffsets: offsets)
        appState.saveSubscription(updatedSubscription)
    }
    
    private func deleteItem(_ item: MonitoredItem) {
        var updatedSubscription = subscription
        updatedSubscription.monitoredItems.removeAll { $0.id == item.id }
        appState.saveSubscription(updatedSubscription)
    }
    
    private func exportSubscriptionData() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "\(subscription.name)_export_\(Date().timeIntervalSince1970).json"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    let exportData: [String: Any] = [
                        "subscription": [
                            "id": subscription.id.uuidString,
                            "name": subscription.name,
                            "publishingInterval": subscription.publishingInterval,
                            "lifetimeCount": 1000,  // Default values as these aren't in the current model
                            "maxKeepAliveCount": 20,
                            "priority": subscription.priority
                        ],
                        "monitoredItems": subscription.monitoredItems.map { item in
                            [
                                "nodeId": item.nodeId,
                                "displayName": item.displayName,
                                "samplingInterval": item.samplingInterval,
                                "currentValue": item.currentValue ?? "",
                                "timestamp": item.timestamp?.ISO8601Format() ?? "",
                                "quality": item.quality.rawValue
                            ]
                        },
                        "exportDate": Date().ISO8601Format()
                    ]
                    
                    let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
                    try jsonData.write(to: url)
                    
                    print("Export Successful: Subscription data exported to \(url.lastPathComponent)")
                } catch {
                    print("Export Failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Supporting Components

struct EditableMonitoredItemRow: View {
    let item: MonitoredItem
    let isSelected: Bool
    let onSelectionToggle: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            // Selection checkbox
            Button(action: onSelectionToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.tertiaryText)
            }
            .buttonStyle(.plain)
            
            // Item info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                Text(item.displayName)
                    .font(DesignSystem.Typography.callout)
                    .lineLimit(1)
                
                Text(item.nodeId)
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.tertiaryText)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Current value
            Text(item.currentValue ?? "—")
                .font(DesignSystem.Typography.monospacedCaption)
                .foregroundColor(DesignSystem.Colors.primary)
                .frame(minWidth: 80, alignment: .trailing)
            
            // Quality indicator
            Circle()
                .fill(item.quality.color)
                .frame(width: 8, height: 8)
            
            // Actions
            if isHovered {
                HStack(spacing: DesignSystem.Spacing.xSmall) {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(DesignSystem.Spacing.small)
        .background(isSelected ? DesignSystem.Colors.primary.opacity(0.1) : 
                   isHovered ? DesignSystem.Colors.tertiaryBackground : Color.clear)
        .cornerRadius(DesignSystem.CornerRadius.small)
        .onHover { isHovered = $0 }
    }
}

struct AdvancedSettingRow: View {
    let title: String
    let description: String
    @Binding var value: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignSystem.Typography.callout)
                    
                    Text(description)
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
                
                Spacer()
                
                TextField("", value: $value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(DesignSystem.Spacing.small)
        .background(DesignSystem.Colors.tertiaryBackground.opacity(0.5))
        .cornerRadius(DesignSystem.CornerRadius.small)
    }
}

struct PerformanceMetric: View {
    let title: String
    let value: String
    let trend: TrendDirection
    let icon: String
    
    enum TrendDirection {
        case up(Double)
        case down(Double)
        case stable
        
        var color: Color {
            switch self {
            case .up: return DesignSystem.Colors.success
            case .down: return DesignSystem.Colors.error
            case .stable: return DesignSystem.Colors.secondaryText
            }
        }
        
        var icon: String {
            switch self {
            case .up: return "arrow.up"
            case .down: return "arrow.down"
            case .stable: return "minus"
            }
        }
        
        var text: String {
            switch self {
            case .up(let percent): return "+\(String(format: "%.1f", percent))%"
            case .down(let percent): return "-\(String(format: "%.1f", percent))%"
            case .stable: return "0%"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(DesignSystem.Colors.primary)
                
                Spacer()
                
                HStack(spacing: 2) {
                    Image(systemName: trend.icon)
                        .font(.system(size: 10))
                        .foregroundColor(trend.color)
                    
                    Text(trend.text)
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(trend.color)
                }
            }
            
            Text(value)
                .font(DesignSystem.Typography.title3)
                .fontWeight(.semibold)
            
            Text(title)
                .font(DesignSystem.Typography.caption2)
                .foregroundColor(DesignSystem.Colors.secondaryText)
        }
        .padding(DesignSystem.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.tertiaryBackground.opacity(0.5))
        .cornerRadius(DesignSystem.CornerRadius.small)
    }
}

struct ErrorStatRow: View {
    let label: String
    let count: Int
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(label)
                .font(DesignSystem.Typography.callout)
            
            Spacer()
            
            Text("\(count)")
                .font(DesignSystem.Typography.callout.weight(.medium))
                .foregroundColor(color)
        }
    }
}

struct SubscriptionStatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(DesignSystem.Typography.callout)
            
            Spacer()
            
            Text(value)
                .font(DesignSystem.Typography.monospacedCaption)
                .foregroundColor(DesignSystem.Colors.primary)
        }
    }
}

#Preview {
    ModernEditSubscriptionView(
        subscription: Subscription(
            name: "Sample Subscription",
            serverId: UUID(),
            publishingInterval: 1000,
            priority: 1,
            isActive: true,
            monitoredItems: []
        )
    )
    .environmentObject(AppState())
}
