import SwiftUI
import Charts

struct ModernSubscriptionsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSubscription: Subscription?
    @State private var showingNewSubscription = false
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .grid
    @State private var showingDeleteConfirmation = false
    @State private var subscriptionToDelete: Subscription?
    @State private var connectionAlertMessage: String?
    @State private var isRefreshingValues = false
    
    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case list = "List"
        
        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }
    
    var filteredSubscriptions: [Subscription] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return appState.subscriptions
        }
        return appState.subscriptions.filter { sub in
            let serverNameMatches = appState.servers
                .first(where: { server in server.id == sub.serverId })?
                .name
                .localizedCaseInsensitiveContains(query) ?? false
            let monitoredItemMatches = sub.monitoredItems.contains {
                $0.displayName.localizedCaseInsensitiveContains(query) ||
                $0.nodeId.localizedCaseInsensitiveContains(query)
            }

            return sub.name.localizedCaseInsensitiveContains(query) ||
                serverNameMatches ||
                monitoredItemMatches
        }
    }

    private var connectedServers: [OPCUAServer] {
        appState.servers.filter { appState.connectionManager.isConnected(to: $0) }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Validation Alert
                if !appState.lastSubscriptionValidationIssues.isEmpty {
                    ModernValidationAlert(validationIssues: appState.lastSubscriptionValidationIssues)
                }

                if connectedServers.isEmpty {
                    SubscriptionConnectionBanner()
                        .padding(.horizontal)
                        .padding(.top, DesignSystem.Spacing.small)
                }
                
                // Main Content
                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.large) {
                        // Header Statistics
                        headerStatistics
                        
                        // View Toggle and Search
                        controlsSection
                        
                        // Subscriptions Grid or List
                        if filteredSubscriptions.isEmpty {
                            emptyState
                        } else {
                            if viewMode == .grid {
                                gridView
                            } else {
                                listView
                            }
                        }
                    }
                    .padding()
                }
                .background(DesignSystem.Colors.tertiaryBackground)
            }
            .navigationTitle("Subscriptions")
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    Button(action: refreshConnectedValues) {
                        Label(isRefreshingValues ? "Refreshing" : "Refresh Values", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRefreshingValues || connectedServers.isEmpty)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: createSubscriptionAction) {
                        Label("New Subscription", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .sheet(isPresented: $showingNewSubscription) {
                ModernNewSubscriptionView()
            }
            .sheet(item: $selectedSubscription) { subscription in
                SubscriptionDetailSheet(subscription: subscription)
            }
            .alert("Delete Subscription", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let subscription = subscriptionToDelete {
                        appState.deleteSubscription(subscription)
                    }
                }
            } message: {
                if let subscription = subscriptionToDelete {
                    Text("Are you sure you want to delete '\(subscription.name)'? This action cannot be undone.")
                }
            }
            .alert("No OPC UA Server Connected", isPresented: .init(
                get: { connectionAlertMessage != nil },
                set: { if !$0 { connectionAlertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { connectionAlertMessage = nil }
            } message: {
                Text(connectionAlertMessage ?? "Connect to an OPC UA server before using this action.")
            }
        }
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                appState.validateCurrentSubscriptions()
                await refreshConnectedValuesAsync()
            }
        }
    }
    
    // MARK: - Header Statistics
    
    var headerStatistics: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            SubscriptionStatCard(
                title: "Total",
                value: "\(appState.subscriptions.count)",
                icon: "bell.badge",
                color: DesignSystem.Colors.primary
            )
            
            SubscriptionStatCard(
                title: "Active",
                value: "\(appState.subscriptions.filter { $0.isActive }.count)",
                icon: "bell.fill",
                color: DesignSystem.Colors.success
            )
            
            SubscriptionStatCard(
                title: "Items",
                value: "\(appState.subscriptions.reduce(0) { $0 + $1.monitoredItems.count })",
                icon: "tag.fill",
                color: DesignSystem.Colors.info
            )
            
            SubscriptionStatCard(
                title: "Servers",
                value: "\(Set(appState.subscriptions.map { $0.serverId }).count)",
                icon: "server.rack",
                color: DesignSystem.Colors.warning
            )
        }
    }
    
    // MARK: - Controls Section
    
    var controlsSection: some View {
        HStack {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DesignSystem.Colors.tertiaryText)
                TextField("Search subscriptions, nodes, or servers...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(DesignSystem.Spacing.xSmall)
            .background(DesignSystem.Colors.background)
            .cornerRadius(DesignSystem.CornerRadius.small)
            
            Spacer()

            Button(action: createSubscriptionAction) {
                Label("Add Subscription", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
            
            // View Mode Toggle
            Picker("View Mode", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 120)
        }
    }
    
    // MARK: - Grid View
    
    var gridView: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 300, maximum: 400), spacing: DesignSystem.Spacing.medium)
        ], spacing: DesignSystem.Spacing.medium) {
            ForEach(filteredSubscriptions) { subscription in
                SubscriptionCard(
                    subscription: subscription,
                    onTap: { viewSubscription(subscription) },
                    onToggle: { toggleSubscription(subscription) },
                    onDelete: {
                        subscriptionToDelete = subscription
                        showingDeleteConfirmation = true
                    },
                    onConnectionIssue: showConnectionIssue
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    // MARK: - List View
    
    var listView: some View {
        VStack(spacing: DesignSystem.Spacing.xSmall) {
            ForEach(filteredSubscriptions) { subscription in
                SubscriptionListRow(
                    subscription: subscription,
                    onTap: { viewSubscription(subscription) },
                    onToggle: { toggleSubscription(subscription) },
                    onDelete: {
                        subscriptionToDelete = subscription
                        showingDeleteConfirmation = true
                    }
                )
                .transition(.slide.combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Empty State
    
    var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Image(systemName: "bell.slash")
                .font(.system(size: 64))
                .foregroundColor(DesignSystem.Colors.tertiaryText)
            
            VStack(spacing: DesignSystem.Spacing.xSmall) {
                Text("No Subscriptions")
                    .font(DesignSystem.Typography.title2)
                
                Text(searchText.isEmpty ? "Create your first subscription to start monitoring OPC UA items" : "No subscriptions match your search")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            
            if searchText.isEmpty {
                Button(action: createSubscriptionAction) {
                    Label("Create Subscription", systemImage: "plus.circle.fill")
                        .font(DesignSystem.Typography.callout.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.xxxLarge)
        .background(DesignSystem.Colors.background)
        .cornerRadius(DesignSystem.CornerRadius.large)
    }
    
    // MARK: - Helper Methods
    
    private func toggleSubscription(_ subscription: Subscription) {
        guard requireConnectedServer(for: subscription, action: "changing subscription state") != nil else {
            return
        }

        var updated = subscription
        updated.isActive.toggle()
        appState.saveSubscription(updated)
    }

    private func createSubscriptionAction() {
        guard !connectedServers.isEmpty else {
            showConnectionIssue("No OPC UA server is connected. Connect to a server before creating a subscription.")
            return
        }
        
        guard connectedServers.count == 1, let server = connectedServers.first else {
            showingNewSubscription = true
            return
        }

        let subscription = Subscription(
            name: nextSubscriptionName(for: server),
            serverId: server.id,
            publishingInterval: 1000,
            priority: 1,
            isActive: true,
            monitoredItems: []
        )

        appState.saveSubscription(subscription)
        Task {
            _ = await appState.connectionManager.createSubscription(for: server, publishingInterval: 1000)
        }
    }

    private func refreshConnectedValues() {
        Task { @MainActor in
            await refreshConnectedValuesAsync()
        }
    }

    private func refreshConnectedValuesAsync() async {
        guard !isRefreshingValues else { return }
        guard !connectedServers.isEmpty else { return }

        isRefreshingValues = true
        await appState.connectionManager.refreshAllConnectedMonitoredItems()
        appState.validateCurrentSubscriptions()
        isRefreshingValues = false
    }

    private func viewSubscription(_ subscription: Subscription) {
        guard requireConnectedServer(for: subscription, action: "viewing subscription details") != nil else {
            return
        }

        selectedSubscription = subscription
    }

    private func requireConnectedServer(for subscription: Subscription, action: String) -> OPCUAServer? {
        guard let server = appState.servers.first(where: { $0.id == subscription.serverId }) else {
            showConnectionIssue("This subscription no longer has a matching server profile.")
            return nil
        }

        guard appState.connectionManager.isConnected(to: server) else {
            showConnectionIssue("No OPC UA server is connected for \(server.name). Connect the server before \(action).")
            return nil
        }

        return server
    }

    private func showConnectionIssue(_ message: String) {
        connectionAlertMessage = message
    }

    private func nextSubscriptionName(for server: OPCUAServer) -> String {
        let baseName = "\(server.name) Live Subscription"
        let existingNames = Set(appState.subscriptions.map(\.name))

        guard existingNames.contains(baseName) else {
            return baseName
        }

        var index = 2
        while existingNames.contains("\(baseName) \(index)") {
            index += 1
        }
        return "\(baseName) \(index)"
    }
}

// MARK: - Subscription Card

struct SubscriptionCard: View {
    let subscription: Subscription
    let onTap: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onConnectionIssue: (String) -> Void
    
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false
    @State private var showingNodePicker = false
    
    var server: OPCUAServer? {
        appState.servers.first { $0.id == subscription.serverId }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                    Text(subscription.name)
                        .font(DesignSystem.Typography.headline)
                        .lineLimit(1)
                    
                    if let server = server {
                        HStack(spacing: DesignSystem.Spacing.xxSmall) {
                            Circle()
                                .fill(appState.connectionManager.isConnected(to: server) ? DesignSystem.Colors.success : DesignSystem.Colors.error)
                                .frame(width: 6, height: 6)
                            Text(server.name)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                        }
                    }
                }
                
                Spacer()
                
                Toggle("", isOn: .init(get: { subscription.isActive }, set: { _ in onToggle() }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(DesignSystem.Spacing.medium)
            
            Divider()
            
            // Statistics
            HStack(spacing: DesignSystem.Spacing.large) {
                StatItem(icon: "tag", value: "\(subscription.monitoredItems.count)", label: "Items")
                StatItem(icon: "timer", value: "\(Int(subscription.publishingInterval))ms", label: "Interval")
                StatItem(icon: "arrow.up.arrow.down", value: "\(subscription.priority)", label: "Priority")
            }
            .padding(DesignSystem.Spacing.medium)
            
            Divider()
            
            // Live Data Preview
            if !subscription.monitoredItems.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                    Text("RECENT VALUES")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(DesignSystem.Colors.tertiaryText)
                    
                    ForEach(subscription.monitoredItems.prefix(3)) { item in
                        HStack {
                            Text(item.displayName)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(item.currentValue ?? "—")
                                .font(DesignSystem.Typography.monospacedCaption)
                                .foregroundColor(DesignSystem.Colors.primaryText)
                        }
                    }
                    
                    if subscription.monitoredItems.count > 3 {
                        Text("+ \(subscription.monitoredItems.count - 3) more")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundColor(DesignSystem.Colors.tertiaryText)
                    }
                }
                .padding(DesignSystem.Spacing.medium)
                .background(DesignSystem.Colors.tertiaryBackground)
            }
            
            // Actions
            HStack(spacing: DesignSystem.Spacing.xSmall) {
                Button(action: openNodePicker) {
                    Label("Add Node", systemImage: "plus.circle")
                        .font(DesignSystem.Typography.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onTap) {
                    Label("View", systemImage: "eye")
                        .font(DesignSystem.Typography.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(DesignSystem.Typography.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(DesignSystem.Colors.error)
            }
            .padding(DesignSystem.Spacing.medium)
        }
        .background(DesignSystem.Colors.background)
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .shadow(color: isHovered ? .black.opacity(0.15) : .black.opacity(0.05), radius: isHovered ? 12 : 6)
        .scaleEffect(isHovered ? 1.02 : 1)
        .onHover { isHovered = $0 }
        .animation(DesignSystem.Animation.fast, value: isHovered)
        .sheet(isPresented: $showingNodePicker) {
            if let server {
                SubscriptionNodePickerSheet(subscription: subscription, server: server)
            }
        }
    }

    private func openNodePicker() {
        guard let server else {
            onConnectionIssue("This subscription no longer has a matching server profile.")
            return
        }

        guard appState.connectionManager.isConnected(to: server) else {
            onConnectionIssue("No OPC UA server is connected for \(server.name). Connect the server before adding a monitored item.")
            return
        }

        showingNodePicker = true
    }
}

// MARK: - List Row

struct SubscriptionListRow: View {
    let subscription: Subscription
    let onTap: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void
    
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false
    
    var server: OPCUAServer? {
        appState.servers.first { $0.id == subscription.serverId }
    }
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            // Status Indicator
            Circle()
                .fill(subscription.isActive ? DesignSystem.Colors.success : DesignSystem.Colors.tertiaryText)
                .frame(width: 10, height: 10)
            
            // Info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                Text(subscription.name)
                    .font(DesignSystem.Typography.headline)
                
                HStack(spacing: DesignSystem.Spacing.small) {
                    if let server = server {
                        Label(server.name, systemImage: "server.rack")
                            .font(DesignSystem.Typography.caption)
                    }
                    
                    Label("\(subscription.monitoredItems.count) items", systemImage: "tag")
                        .font(DesignSystem.Typography.caption)
                    
                    Label("\(Int(subscription.publishingInterval))ms", systemImage: "timer")
                        .font(DesignSystem.Typography.caption)
                }
                .foregroundColor(DesignSystem.Colors.secondaryText)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: DesignSystem.Spacing.small) {
                Toggle("", isOn: .init(get: { subscription.isActive }, set: { _ in onToggle() }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                
                Button(action: onTap) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.background)
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .shadow(color: isHovered ? .black.opacity(0.1) : .black.opacity(0.03), radius: isHovered ? 8 : 4)
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
    }
}

// MARK: - Stat Components

struct SubscriptionStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(DesignSystem.Typography.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
        }
        .padding(DesignSystem.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.background)
        .cornerRadius(DesignSystem.CornerRadius.medium)
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xxSmall) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(DesignSystem.Colors.primary)
            
            Text(value)
                .font(DesignSystem.Typography.callout.weight(.semibold))
            
            Text(label)
                .font(DesignSystem.Typography.caption2)
                .foregroundColor(DesignSystem.Colors.tertiaryText)
        }
    }
}

// MARK: - Validation Alert

struct ModernValidationAlert: View {
    let validationIssues: [MonitoredItemValidation]
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(DesignSystem.Colors.warning)
                
                Text("\(validationIssues.count) validation issue\(validationIssues.count == 1 ? "" : "s") found")
                    .font(DesignSystem.Typography.callout.weight(.medium))
                
                Spacer()
                
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                    ForEach(Array(validationIssues.prefix(5)), id: \.nodeId) { issue in
                        HStack {
                            Circle()
                                .fill(DesignSystem.Colors.warning)
                                .frame(width: 6, height: 6)
                            
                            Text(issue.nodeId)
                                .font(DesignSystem.Typography.caption)
                            
                            Text("—")
                                .foregroundColor(DesignSystem.Colors.tertiaryText)
                            
                            if let description = issue.issue?.description {
                                Text(description)
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.secondaryText)
                            }
                        }
                    }
                    
                    if validationIssues.count > 5 {
                        Text("+ \(validationIssues.count - 5) more issues")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundColor(DesignSystem.Colors.tertiaryText)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.warning.opacity(0.1))
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .stroke(DesignSystem.Colors.warning.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.top, DesignSystem.Spacing.small)
    }
}

struct SubscriptionConnectionBanner: View {
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(DesignSystem.Colors.warning)
                .font(.title3)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                Text("No OPC UA server connected")
                    .font(DesignSystem.Typography.callout.weight(.semibold))
                Text("Connect to a server before creating, viewing, or changing subscriptions.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.warning.opacity(0.1))
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .stroke(DesignSystem.Colors.warning.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Subscription Detail Sheet

struct SubscriptionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    let subscription: Subscription
    @State private var connectionAlertMessage: String?
    @State private var showingNodePicker = false

    private var currentSubscription: Subscription {
        appState.subscriptions.first { $0.id == subscription.id } ?? subscription
    }

    private var server: OPCUAServer? {
        appState.servers.first { $0.id == currentSubscription.serverId }
    }

    private var isConnected: Bool {
        guard let server else { return false }
        return appState.connectionManager.isConnected(to: server)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                    detailHeader
                    metricRow
                    monitoredItemsSection
                }
                .padding()
            }
            .background(DesignSystem.Colors.tertiaryBackground)
            .navigationTitle(currentSubscription.name)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: openNodePicker) {
                        Label("Add Node", systemImage: "plus.circle")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("No OPC UA Server Connected", isPresented: .init(
                get: { connectionAlertMessage != nil },
                set: { if !$0 { connectionAlertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { connectionAlertMessage = nil }
            } message: {
                Text(connectionAlertMessage ?? "Connect to an OPC UA server before using this action.")
            }
            .sheet(isPresented: $showingNodePicker) {
                if let server {
                    SubscriptionNodePickerSheet(subscription: currentSubscription, server: server)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 560)
        #endif
        .onAppear {
            guard let server, isConnected else { return }
            Task { @MainActor in
                await appState.connectionManager.refreshMonitoredItems(for: server)
            }
        }
    }

    private var detailHeader: some View {
        ModernCard {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
                Image(systemName: "bell.badge")
                    .font(.title2)
                    .foregroundColor(DesignSystem.Colors.primary)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                    Text(currentSubscription.name)
                        .font(DesignSystem.Typography.title2)
                    Text(server?.name ?? "Missing server profile")
                        .font(DesignSystem.Typography.callout)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

                    HStack(spacing: DesignSystem.Spacing.xSmall) {
                        Circle()
                            .fill(isConnected ? DesignSystem.Colors.success : DesignSystem.Colors.error)
                            .frame(width: 8, height: 8)
                        Text(isConnected ? "Connected" : "No server connected")
                            .font(DesignSystem.Typography.caption.weight(.medium))
                            .foregroundColor(isConnected ? DesignSystem.Colors.success : DesignSystem.Colors.error)
                    }
                }

                Spacer()
            }
        }
    }

    private var metricRow: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            SubscriptionStatCard(
                title: "Items",
                value: "\(currentSubscription.monitoredItems.count)",
                icon: "tag.fill",
                color: DesignSystem.Colors.info
            )

            SubscriptionStatCard(
                title: "Interval",
                value: "\(Int(currentSubscription.publishingInterval))ms",
                icon: "timer",
                color: DesignSystem.Colors.primary
            )

            SubscriptionStatCard(
                title: "Priority",
                value: "\(currentSubscription.priority)",
                icon: "arrow.up.arrow.down",
                color: DesignSystem.Colors.warning
            )
        }
    }

    private var monitoredItemsSection: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                HStack {
                    SectionHeader("MONITORED ITEMS", icon: "tag")
                    Spacer()
                    Button(action: openNodePicker) {
                        Label("Add Node", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                }

                if currentSubscription.monitoredItems.isEmpty {
                    VStack(spacing: DesignSystem.Spacing.small) {
                        Image(systemName: "tag.slash")
                            .font(.largeTitle)
                            .foregroundColor(DesignSystem.Colors.tertiaryText)
                        Text("No monitored items")
                            .font(DesignSystem.Typography.headline)
                        Text(isConnected ? "Add a node to start receiving live subscription values." : "Connect the OPC UA server before adding monitored items.")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DesignSystem.Spacing.xLarge)
                } else {
                    VStack(spacing: DesignSystem.Spacing.small) {
                        ForEach(currentSubscription.monitoredItems) { item in
                            monitoredItemRow(item)
                        }
                    }
                }
            }
        }
    }

    private func monitoredItemRow(_ item: MonitoredItem) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
            Image(systemName: "waveform.path.ecg")
                .foregroundColor(item.quality.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                Text(item.displayName)
                    .font(DesignSystem.Typography.callout.weight(.medium))
                Text(item.nodeId)
                    .font(DesignSystem.Typography.monospacedCaption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: DesignSystem.Spacing.xxSmall) {
                Text(item.currentValue?.isEmpty == false ? item.currentValue! : "Waiting")
                    .font(DesignSystem.Typography.monospacedBody)
                Text(item.timestamp?.formatted(date: .omitted, time: .standard) ?? item.quality.rawValue)
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        }
        .padding(DesignSystem.Spacing.small)
        .background(DesignSystem.Colors.tertiaryBackground)
        .cornerRadius(DesignSystem.CornerRadius.small)
    }

    private func openNodePicker() {
        guard let server else {
            connectionAlertMessage = "This subscription no longer has a matching server profile."
            return
        }

        guard appState.connectionManager.isConnected(to: server) else {
            connectionAlertMessage = "No OPC UA server is connected for \(server.name). Connect the server before adding a monitored item."
            return
        }

        showingNodePicker = true
    }
}

// MARK: - Subscription Node Picker

struct SubscriptionNodePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    let subscription: Subscription
    let server: OPCUAServer

    @State private var rootNodes: [NodeInfo] = []
    @State private var childrenByNodeId: [String: [NodeInfo]] = [:]
    @State private var expandedNodeIds = Set<String>()
    @State private var loadingNodeIds = Set<String>()
    @State private var selectedNode: NodeInfo?
    @State private var searchText = ""
    @State private var samplingInterval = "1000"
    @State private var queueSize = "10"
    @State private var isLoadingRoot = false
    @State private var isValidating = false
    @State private var isAdding = false
    @State private var previewValue: String?
    @State private var errorMessage: String?
    @State private var validationMessage: String?

    private var currentSubscription: Subscription {
        appState.subscriptions.first { $0.id == subscription.id } ?? subscription
    }

    private var selectableLoadedNodes: [NodeInfo] {
        flatten(rootNodes).filter { isSubscribable($0) }
    }

    private var filteredSelectableNodes: [NodeInfo] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return selectableLoadedNodes }
        return selectableLoadedNodes.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed) ||
            $0.nodeId.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var selectedNodeIsDuplicate: Bool {
        guard let selectedNode else { return false }
        return currentSubscription.monitoredItems.contains { $0.nodeId == selectedNode.nodeId }
    }

    private var samplingIntervalValue: Double? {
        Double(samplingInterval.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var queueSizeValue: Int? {
        Int(queueSize.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canAddSelectedNode: Bool {
        selectedNode != nil &&
        previewValue != nil &&
        !selectedNodeIsDuplicate &&
        samplingIntervalValue != nil &&
        queueSizeValue != nil &&
        !isAdding &&
        !isValidating
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                browserPane
                    .frame(minWidth: 380, idealWidth: 460)

                Divider()

                selectionPane
                    .frame(minWidth: 300, idealWidth: 360)
            }
            .navigationTitle("Add Subscribable Node")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isAdding ? "Adding..." : "Add Node", action: addSelectedNode)
                        .disabled(!canAddSelectedNode)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 820, minHeight: 620)
        #endif
        .onAppear(perform: loadRootNodes)
    }

    private var browserPane: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                Text(server.name)
                    .font(DesignSystem.Typography.headline)
                Text("Only Variable nodes with readable values can be added to a subscription.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DesignSystem.Colors.tertiaryText)
                TextField("Search loaded variables...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(DesignSystem.Spacing.xSmall)
            .background(DesignSystem.Colors.tertiaryBackground)
            .cornerRadius(DesignSystem.CornerRadius.small)

            if isLoadingRoot {
                VStack(spacing: DesignSystem.Spacing.small) {
                    ProgressView()
                    Text("Loading address space...")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.xSmall) {
                        ForEach(filteredSelectableNodes) { node in
                            SubscribableNodeSearchRow(
                                node: node,
                                isSelected: selectedNode?.nodeId == node.nodeId,
                                isDuplicate: currentSubscription.monitoredItems.contains { $0.nodeId == node.nodeId },
                                onSelect: { selectNode(node) }
                            )
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.xSmall)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                        ForEach(rootNodes.filter(isVisibleInPicker)) { node in
                            SubscribableNodeTreeRow(
                                node: node,
                                level: 0,
                                selectedNodeId: selectedNode?.nodeId,
                                expandedNodeIds: expandedNodeIds,
                                loadingNodeIds: loadingNodeIds,
                                childrenByNodeId: childrenByNodeId,
                                duplicateNodeIds: Set(currentSubscription.monitoredItems.map(\.nodeId)),
                                onToggle: toggleNode,
                                onSelect: selectNode
                            )
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.xSmall)
                }
            }
        }
        .padding()
        .background(DesignSystem.Colors.background)
    }

    private var selectionPane: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                SectionHeader("SELECTION", icon: "tag")

                if let selectedNode {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                        Text(selectedNode.displayName)
                            .font(DesignSystem.Typography.headline)
                        Text(selectedNode.nodeId)
                            .font(DesignSystem.Typography.monospacedCaption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)

                        if selectedNodeIsDuplicate {
                            Label("Already monitored by this subscription", systemImage: "checkmark.circle.fill")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.warning)
                        } else if isValidating {
                            Label("Checking current value...", systemImage: "hourglass")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                        } else if let previewValue {
                            Label("Readable value: \(previewValue)", systemImage: "checkmark.circle.fill")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.success)
                        } else if let validationMessage {
                            Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.error)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignSystem.Colors.tertiaryBackground)
                    .cornerRadius(DesignSystem.CornerRadius.medium)
                } else {
                    Text("Select a Variable node from the address space.")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignSystem.Colors.tertiaryBackground)
                        .cornerRadius(DesignSystem.CornerRadius.medium)
                }
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                SectionHeader("SAMPLING", icon: "timer")

                ModernTextField(
                    title: "Sampling Interval (ms)",
                    text: $samplingInterval,
                    icon: "timer",
                    placeholder: "1000"
                )

                ModernTextField(
                    title: "Queue Size",
                    text: $queueSize,
                    icon: "square.stack.3d.up",
                    placeholder: "10"
                )
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.error)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignSystem.Colors.error.opacity(0.1))
                    .cornerRadius(DesignSystem.CornerRadius.small)
            }

            Spacer()
        }
        .padding()
        .background(DesignSystem.Colors.tertiaryBackground)
    }

    private func loadRootNodes() {
        guard rootNodes.isEmpty, !isLoadingRoot else { return }
        guard appState.connectionManager.isConnected(to: server) else {
            errorMessage = "No OPC UA server is connected."
            return
        }

        isLoadingRoot = true
        errorMessage = nil

        Task {
            let nodes = await appState.connectionManager.browseAddressSpace(for: server, maxDepth: 1)
                .filter(isVisibleInPicker)

            await MainActor.run {
                rootNodes = nodes
                isLoadingRoot = false
            }
        }
    }

    private func toggleNode(_ node: NodeInfo) {
        guard isExpandable(node) else {
            selectNode(node)
            return
        }

        if expandedNodeIds.contains(node.nodeId) {
            expandedNodeIds.remove(node.nodeId)
            return
        }

        expandedNodeIds.insert(node.nodeId)

        guard childrenByNodeId[node.nodeId] == nil, !loadingNodeIds.contains(node.nodeId) else {
            return
        }

        loadingNodeIds.insert(node.nodeId)

        Task {
            let children = await appState.connectionManager.browseChildNodes(for: server, parentNodeId: node.nodeId)
                .filter(isVisibleInPicker)

            await MainActor.run {
                childrenByNodeId[node.nodeId] = children
                loadingNodeIds.remove(node.nodeId)
            }
        }
    }

    private func selectNode(_ node: NodeInfo) {
        guard isSubscribable(node) else {
            validationMessage = "Only Variable nodes can be subscribed."
            return
        }

        selectedNode = node
        previewValue = nil
        validationMessage = nil
        errorMessage = nil

        guard !currentSubscription.monitoredItems.contains(where: { $0.nodeId == node.nodeId }) else {
            validationMessage = "This node is already monitored by the subscription."
            return
        }

        isValidating = true

        Task {
            let value = await appState.connectionManager.readValue(for: server, nodeId: node.nodeId)

            await MainActor.run {
                guard selectedNode?.nodeId == node.nodeId else { return }
                isValidating = false
                if let value, !value.isEmpty {
                    previewValue = value
                } else {
                    validationMessage = "This Variable could not be read, so it is not selectable for monitoring."
                }
            }
        }
    }

    private func addSelectedNode() {
        guard let selectedNode else { return }
        guard let samplingIntervalValue, let queueSizeValue else {
            errorMessage = "Enter valid sampling interval and queue size values."
            return
        }
        guard appState.connectionManager.isConnected(to: server) else {
            errorMessage = "No OPC UA server is connected."
            return
        }

        isAdding = true
        errorMessage = nil

        Task {
            let success = await appState.connectionManager.addMonitoredItem(
                for: server,
                nodeId: selectedNode.nodeId,
                samplingInterval: samplingIntervalValue
            )

            await MainActor.run {
                if success {
                    let item = MonitoredItem(
                        nodeId: selectedNode.nodeId,
                        displayName: selectedNode.displayName,
                        samplingInterval: samplingIntervalValue,
                        queueSize: queueSizeValue,
                        discardOldest: true,
                        currentValue: previewValue,
                        timestamp: previewValue == nil ? nil : Date(),
                        quality: previewValue == nil ? .uncertain : .good
                    )
                    appState.addMonitoredItem(item, to: currentSubscription.id)
                    dismiss()
                } else {
                    isAdding = false
                    errorMessage = "The server rejected the monitored item. Pick a readable Variable node and try again."
                }
            }
        }
    }

    private func isVisibleInPicker(_ node: NodeInfo) -> Bool {
        isSubscribable(node) || isExpandable(node)
    }

    private func isExpandable(_ node: NodeInfo) -> Bool {
        node.nodeClass == .object || node.nodeClass == .view
    }

    private func isSubscribable(_ node: NodeInfo) -> Bool {
        node.nodeClass == .variable
    }

    private func flatten(_ nodes: [NodeInfo]) -> [NodeInfo] {
        nodes.flatMap { node -> [NodeInfo] in
            [node] + flatten(childrenByNodeId[node.nodeId] ?? node.children ?? [])
        }
    }
}

private struct SubscribableNodeTreeRow: View {
    let node: NodeInfo
    let level: Int
    let selectedNodeId: String?
    let expandedNodeIds: Set<String>
    let loadingNodeIds: Set<String>
    let childrenByNodeId: [String: [NodeInfo]]
    let duplicateNodeIds: Set<String>
    let onToggle: (NodeInfo) -> Void
    let onSelect: (NodeInfo) -> Void

    private var isExpanded: Bool { expandedNodeIds.contains(node.nodeId) }
    private var isLoading: Bool { loadingNodeIds.contains(node.nodeId) }
    private var isSubscribable: Bool { node.nodeClass == .variable }
    private var isExpandable: Bool { node.nodeClass == .object || node.nodeClass == .view }
    private var isSelected: Bool { selectedNodeId == node.nodeId }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
            Button(action: { isSubscribable ? onSelect(node) : onToggle(node) }) {
                HStack(spacing: DesignSystem.Spacing.xSmall) {
                    if isExpandable {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 14)
                    } else {
                        Color.clear.frame(width: 14, height: 1)
                    }

                    Image(systemName: isSubscribable ? "waveform.path.ecg" : "folder")
                        .foregroundColor(isSubscribable ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.displayName)
                            .font(DesignSystem.Typography.callout)
                            .lineLimit(1)
                        Text(node.nodeId)
                            .font(DesignSystem.Typography.monospacedCaption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    if duplicateNodeIds.contains(node.nodeId) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(DesignSystem.Colors.warning)
                    } else if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else if isSubscribable {
                        Image(systemName: "plus.circle")
                            .foregroundColor(DesignSystem.Colors.primary)
                    }
                }
                .padding(DesignSystem.Spacing.xSmall)
                .background(isSelected ? DesignSystem.Colors.primary.opacity(0.12) : Color.clear)
                .cornerRadius(DesignSystem.CornerRadius.small)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, CGFloat(level) * 18)

            if isExpanded {
                ForEach((childrenByNodeId[node.nodeId] ?? node.children ?? []).filter { child in
                    child.nodeClass == .variable || child.nodeClass == .object || child.nodeClass == .view
                }) { child in
                    SubscribableNodeTreeRow(
                        node: child,
                        level: level + 1,
                        selectedNodeId: selectedNodeId,
                        expandedNodeIds: expandedNodeIds,
                        loadingNodeIds: loadingNodeIds,
                        childrenByNodeId: childrenByNodeId,
                        duplicateNodeIds: duplicateNodeIds,
                        onToggle: onToggle,
                        onSelect: onSelect
                    )
                }
            }
        }
    }
}

private struct SubscribableNodeSearchRow: View {
    let node: NodeInfo
    let isSelected: Bool
    let isDuplicate: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignSystem.Spacing.small) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(DesignSystem.Colors.success)

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.displayName)
                        .font(DesignSystem.Typography.callout)
                    Text(node.nodeId)
                        .font(DesignSystem.Typography.monospacedCaption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }

                Spacer()

                if isDuplicate {
                    Text("Added")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(DesignSystem.Colors.warning)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.primary)
                }
            }
            .padding(DesignSystem.Spacing.small)
            .background(isSelected ? DesignSystem.Colors.primary.opacity(0.12) : DesignSystem.Colors.tertiaryBackground)
            .cornerRadius(DesignSystem.CornerRadius.small)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - New Subscription View

struct ModernNewSubscriptionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @State private var name = ""
    @State private var selectedServer: OPCUAServer?
    @State private var publishingInterval = "1000"
    @State private var priority = 1
    @State private var isActive = true
    
    var connectedServers: [OPCUAServer] {
        appState.servers.filter { server in
            appState.connectionManager.getConnectionStatus(for: server) == .connected
        }
    }
    
    var isValid: Bool {
        !name.isEmpty && selectedServer != nil
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.large) {
                    // Info Card
                    ModernCard {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(DesignSystem.Colors.info)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                                Text("Create a new subscription")
                                    .font(DesignSystem.Typography.callout.weight(.medium))
                                Text("Monitor OPC UA variables in real-time with custom update intervals")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.secondaryText)
                            }
                            
                            Spacer()
                        }
                    }
                    
                    // Basic Settings
                    ModernCard {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                            SectionHeader("BASIC SETTINGS", icon: "gearshape")
                            
                            ModernTextField(title: "Subscription Name", text: $name, placeholder: "e.g., Temperature Monitoring")
                            
                            ModernPicker(
                                "Server",
                                selection: $selectedServer
                            ) {
                                ForEach(connectedServers) { server in
                                    Text(server.name).tag(Optional(server))
                                }
                            }
                            
                            if connectedServers.isEmpty {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(DesignSystem.Colors.warning)
                                    Text("No servers connected. Connect to a server first.")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.secondaryText)
                                }
                                .padding(DesignSystem.Spacing.small)
                                .background(DesignSystem.Colors.warning.opacity(0.1))
                                .cornerRadius(DesignSystem.CornerRadius.small)
                            }
                        }
                    }
                    
                    // Publishing Settings
                    ModernCard {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                            SectionHeader("PUBLISHING SETTINGS", icon: "timer")
                            
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                                Text("Publishing Interval")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.secondaryText)
                                
                                HStack {
                                    TextField("1000", text: $publishingInterval)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 100)
                                    
                                    Text("ms")
                                        .foregroundColor(DesignSystem.Colors.secondaryText)
                                    
                                    Spacer()
                                    
                                    // Quick presets
                                    HStack(spacing: DesignSystem.Spacing.xSmall) {
                                        ForEach(["250", "500", "1000", "5000"], id: \.self) { interval in
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
                            
                            HStack {
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                                    Text("Priority")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.secondaryText)
                                    
                                    Stepper("\(priority)", value: $priority, in: 0...255)
                                }
                                
                                Spacer()
                                
                                Toggle("Start Active", isOn: $isActive)
                                    .toggleStyle(.switch)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(DesignSystem.Colors.tertiaryBackground)
            .navigationTitle("New Subscription")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createSubscription()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
        .onAppear {
            if selectedServer == nil {
                selectedServer = connectedServers.first
            }
        }
    }
    
    private func createSubscription() {
        guard let server = selectedServer,
              let interval = Double(publishingInterval) else { return }
        
        let newSubscription = Subscription(
            name: name,
            serverId: server.id,
            publishingInterval: interval,
            priority: priority,
            isActive: isActive,
            monitoredItems: []
        )
        
        appState.saveSubscription(newSubscription)

        if isActive {
            Task {
                _ = await appState.connectionManager.createSubscription(
                    for: server,
                    publishingInterval: interval
                )
            }
        }
    }
}

// MARK: - Edit Subscription View

struct InlineEditSubscriptionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    let subscription: Subscription
    @State private var showingNodePicker = false
    @State private var connectionAlertMessage: String?

    private var currentSubscription: Subscription {
        appState.subscriptions.first { $0.id == subscription.id } ?? subscription
    }

    private var server: OPCUAServer? {
        appState.servers.first { $0.id == currentSubscription.serverId }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: DesignSystem.Spacing.medium) {
                    SubscriptionStatCard(
                        title: "Items",
                        value: "\(currentSubscription.monitoredItems.count)",
                        icon: "tag.fill",
                        color: DesignSystem.Colors.info
                    )

                    SubscriptionStatCard(
                        title: "Interval",
                        value: "\(Int(currentSubscription.publishingInterval))ms",
                        icon: "timer",
                        color: DesignSystem.Colors.primary
                    )

                    SubscriptionStatCard(
                        title: "Priority",
                        value: "\(currentSubscription.priority)",
                        icon: "arrow.up.arrow.down",
                        color: DesignSystem.Colors.warning
                    )
                }
                .padding()

                Divider()

                if currentSubscription.monitoredItems.isEmpty {
                    DesignSystemEmptyStateView(
                        icon: "tag.slash",
                        title: "No Monitored Items",
                        message: "Add a node to start receiving live subscription values",
                        action: openNodePicker,
                        actionLabel: "Add Node"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        ForEach(currentSubscription.monitoredItems) { item in
                            ModernMonitoredItemRow(item: item)
                        }
                        .onDelete { offsets in
                            deleteItems(at: offsets)
                        }
                    }
                }
            }
            .navigationTitle(subscription.name)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: openNodePicker) {
                        Label("Add Node", systemImage: "plus.circle")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("No OPC UA Server Connected", isPresented: .init(
                get: { connectionAlertMessage != nil },
                set: { if !$0 { connectionAlertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { connectionAlertMessage = nil }
            } message: {
                Text(connectionAlertMessage ?? "Connect to an OPC UA server before adding a monitored item.")
            }
            .sheet(isPresented: $showingNodePicker) {
                if let server {
                    SubscriptionNodePickerSheet(subscription: currentSubscription, server: server)
                }
            }
        }
        #if os(macOS)
        .frame(width: 820, height: 620)
        #endif
    }

    private func deleteItems(at offsets: IndexSet) {
        var updated = currentSubscription
        updated.monitoredItems.remove(atOffsets: offsets)
        appState.saveSubscription(updated)
    }

    private func openNodePicker() {
        guard let server else {
            connectionAlertMessage = "This subscription no longer has a matching server profile."
            return
        }

        guard appState.connectionManager.isConnected(to: server) else {
            connectionAlertMessage = "No OPC UA server is connected for \(server.name). Connect the server before adding a monitored item."
            return
        }

        showingNodePicker = true
    }
}

// MARK: - Tabs

struct MonitoredItemsTab: View {
    let subscription: Subscription
    @EnvironmentObject var appState: AppState
    @State private var showingNodePicker = false
    @State private var connectionAlertMessage: String?
    
    var currentSubscription: Subscription? {
        appState.subscriptions.first { $0.id == subscription.id }
    }

    private var server: OPCUAServer? {
        guard let currentSubscription else { return nil }
        return appState.servers.first { $0.id == currentSubscription.serverId }
    }
    
    var body: some View {
        VStack {
            if let current = currentSubscription, !current.monitoredItems.isEmpty {
                List {
                    ForEach(current.monitoredItems) { item in
                        ModernMonitoredItemRow(item: item)
                    }
                    .onDelete { offsets in
                        deleteItems(at: offsets)
                    }
                }
            } else {
                DesignSystemEmptyStateView(
                    icon: "tag.slash",
                    title: "No Monitored Items",
                    message: "Add items to monitor their values in real-time",
                    action: openNodePicker,
                    actionLabel: "Add Node"
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: openNodePicker) {
                    Label("Add Node", systemImage: "plus.circle")
                }
            }
        }
        .alert("No OPC UA Server Connected", isPresented: .init(
            get: { connectionAlertMessage != nil },
            set: { if !$0 { connectionAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { connectionAlertMessage = nil }
        } message: {
            Text(connectionAlertMessage ?? "Connect to an OPC UA server before adding a monitored item.")
        }
        .sheet(isPresented: $showingNodePicker) {
            if let currentSubscription, let server {
                SubscriptionNodePickerSheet(subscription: currentSubscription, server: server)
            }
        }
    }
    
    private func deleteItems(at offsets: IndexSet) {
        guard let current = currentSubscription else { return }
        
        var updated = current
        updated.monitoredItems.remove(atOffsets: offsets)
        appState.saveSubscription(updated)
    }

    private func openNodePicker() {
        guard let server else {
            connectionAlertMessage = "This subscription no longer has a matching server profile."
            return
        }

        guard appState.connectionManager.isConnected(to: server) else {
            connectionAlertMessage = "No OPC UA server is connected for \(server.name). Connect the server before adding a monitored item."
            return
        }

        showingNodePicker = true
    }
}

struct ModernMonitoredItemRow: View {
    let item: MonitoredItem
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                Text(item.displayName)
                    .font(DesignSystem.Typography.callout)
                
                Text(item.nodeId)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: DesignSystem.Spacing.xxSmall) {
                Text(item.currentValue ?? "—")
                    .font(DesignSystem.Typography.monospacedBody)
                
                HStack(spacing: DesignSystem.Spacing.xxSmall) {
                    Circle()
                        .fill(item.quality.color)
                        .frame(width: 6, height: 6)
                    
                    Text(item.quality.rawValue)
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(DesignSystem.Colors.tertiaryText)
                }
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xxSmall)
    }
}

struct ConfigurationTab: View {
    let subscription: Subscription
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.large) {
                ModernCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        SectionHeader("PUBLISHING", icon: "arrow.triangle.2.circlepath")
                        
                        LabeledValue(label: "Interval", value: "\(Int(subscription.publishingInterval)) ms")
                        LabeledValue(label: "Priority", value: "\(subscription.priority)")
                        LabeledValue(label: "Status", value: subscription.isActive ? "Active" : "Inactive")
                    }
                }
                
                ModernCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        SectionHeader("MONITORING", icon: "eye")
                        
                        LabeledValue(label: "Items Count", value: "\(subscription.monitoredItems.count)")
                        LabeledValue(label: "Server ID", value: subscription.serverId.uuidString)
                    }
                }
            }
            .padding()
        }
        .background(DesignSystem.Colors.tertiaryBackground)
    }
}

struct StatisticsTab: View {
    let subscription: Subscription
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.large) {
                // Mock statistics - would be real data in production
                ModernCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        SectionHeader("PERFORMANCE", icon: "speedometer")
                        
                        LabeledValue(label: "Messages/sec", value: "45")
                        LabeledValue(label: "Avg Latency", value: "12 ms")
                        LabeledValue(label: "Data Rate", value: "2.3 KB/s")
                    }
                }
                
                ModernCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        SectionHeader("RELIABILITY", icon: "checkmark.shield")
                        
                        LabeledValue(label: "Uptime", value: "99.9%")
                        LabeledValue(label: "Errors", value: "0")
                        LabeledValue(label: "Timeouts", value: "0")
                    }
                }
            }
            .padding()
        }
        .background(DesignSystem.Colors.tertiaryBackground)
    }
}

struct LabeledValue: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(DesignSystem.Typography.callout)
                .foregroundColor(DesignSystem.Colors.secondaryText)
            
            Spacer()
            
            Text(value)
                .font(DesignSystem.Typography.callout.weight(.medium))
        }
    }
}

#Preview {
    ModernSubscriptionsView()
        .environmentObject(AppState())
}
