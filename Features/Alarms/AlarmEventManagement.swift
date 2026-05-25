import SwiftUI
import UserNotifications
import Combine

struct AlarmEventManagementView: View {
    @StateObject private var alarmManager = AlarmEventManager.shared
    @State private var selectedTab = AlarmTab.active
    @State private var selectedSeverity = Set<AlarmSeverity>()
    @State private var searchText = ""
    @State private var showingAlarmDetails = false
    @State private var selectedAlarm: Alarm?
    @State private var showingSettings = false

    init(selectedItemID: String? = nil) {
        let tab: AlarmTab
        switch selectedItemID {
        case "event-stream":
            tab = .events
        case "condition-refresh":
            tab = .history
        default:
            tab = .active
        }
        _selectedTab = State(initialValue: tab)
    }
    
    enum AlarmTab: String, CaseIterable {
        case active = "Active"
        case history = "History" 
        case acknowledged = "Acknowledged"
        case events = "Events"
        
        var icon: String {
            switch self {
            case .active: return "bell.badge"
            case .history: return "clock"
            case .acknowledged: return "checkmark.circle"
            case .events: return "list.bullet.rectangle"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            tabSelector
            contentView
        }
        .background(
            AnimatedGradientBackground(colors: [
                Color(hex: "0F172A").opacity(0.95),
                Color(hex: "1E293B").opacity(0.95)
            ])
        )
        .navigationTitle("Alarms & Events")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Settings") { showingSettings = true }
                    Button("Export Log") { alarmManager.exportAlarmLog() }
                    Button("Clear History") { alarmManager.clearHistory() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            AlarmSettingsView(manager: alarmManager)
        }
        .sheet(isPresented: $showingAlarmDetails) {
            if let alarm = selectedAlarm {
                AlarmDetailView(alarm: alarm, manager: alarmManager)
            }
        }
        .onAppear {
            alarmManager.requestNotificationPermission()
        }
    }
    
    var headerView: some View {
        VStack(spacing: OPCTheme.Spacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: OPCTheme.Spacing.xs) {
                    Text("Alarm & Event Center")
                        .font(OPCTheme.Typography.title2)
                        .fontWeight(.bold)
                        .foregroundColor(OPCTheme.Colors.text)
                    
                    Text("\(alarmManager.activeAlarms.count) active alarms")
                        .font(OPCTheme.Typography.subheadline)
                        .foregroundColor(OPCTheme.Colors.secondaryText)
                }
                
                Spacer()
                
                AlarmSummaryIndicator(manager: alarmManager)
            }
            
            HStack(spacing: OPCTheme.Spacing.md) {
                SearchBar(text: $searchText, placeholder: "Search alarms...")
                
                Menu {
                    Text("Filter by Severity")
                    
                    ForEach(AlarmSeverity.allCases, id: \.self) { severity in
                        Button {
                            if selectedSeverity.contains(severity) {
                                selectedSeverity.remove(severity)
                            } else {
                                selectedSeverity.insert(severity)
                            }
                        } label: {
                            HStack {
                                if selectedSeverity.contains(severity) {
                                    Image(systemName: "checkmark")
                                }
                                
                                HStack {
                                    Circle()
                                        .fill(severity.color)
                                        .frame(width: 8, height: 8)
                                    Text(severity.rawValue)
                                }
                            }
                        }
                    }
                    
                    if !selectedSeverity.isEmpty {
                        Divider()
                        Button("Clear Filter") {
                            selectedSeverity.removeAll()
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 20))
                        .foregroundColor(selectedSeverity.isEmpty ? OPCTheme.Colors.secondaryText : OPCTheme.Colors.primary)
                }
            }
        }
        .padding()
        .background(OPCTheme.Colors.secondaryBackground)
    }
    
    var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(AlarmTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: OPCTheme.Spacing.xs) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14))
                        Text(tab.rawValue)
                            .font(OPCTheme.Typography.callout)
                    }
                    .foregroundColor(selectedTab == tab ? OPCTheme.Colors.primary : OPCTheme.Colors.secondaryText)
                    .padding(.vertical, OPCTheme.Spacing.md)
                    .frame(maxWidth: .infinity)
                    .background(
                        selectedTab == tab ?
                        Rectangle()
                            .fill(OPCTheme.Colors.primary.opacity(0.1))
                        : nil
                    )
                    .overlay(
                        Rectangle()
                            .fill(OPCTheme.Colors.primary)
                            .frame(height: 2),
                        alignment: .bottom
                    )
                    .opacity(selectedTab == tab ? 1 : 0)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(OPCTheme.Colors.tertiaryBackground)
    }
    
    @ViewBuilder
    var contentView: some View {
        switch selectedTab {
        case .active:
            AlarmListView(
                alarms: filteredActiveAlarms,
                onAlarmTap: { alarm in
                    selectedAlarm = alarm
                    showingAlarmDetails = true
                },
                onAcknowledge: { alarm in
                    alarmManager.acknowledgeAlarm(alarm)
                }
            )
            
        case .history:
            AlarmHistoryView(
                alarms: filteredHistoryAlarms,
                onAlarmTap: { alarm in
                    selectedAlarm = alarm
                    showingAlarmDetails = true
                }
            )
            
        case .acknowledged:
            AlarmListView(
                alarms: filteredAcknowledgedAlarms,
                onAlarmTap: { alarm in
                    selectedAlarm = alarm
                    showingAlarmDetails = true
                },
                showAcknowledgeButton: false
            )
            
        case .events:
            EventListView(events: filteredEvents)
        }
    }
    
    var filteredActiveAlarms: [Alarm] {
        alarmManager.activeAlarms.filter { alarm in
            (searchText.isEmpty || alarm.message.localizedCaseInsensitiveContains(searchText) ||
             alarm.source.localizedCaseInsensitiveContains(searchText)) &&
            (selectedSeverity.isEmpty || selectedSeverity.contains(alarm.severity))
        }
    }
    
    var filteredHistoryAlarms: [Alarm] {
        alarmManager.alarmHistory.filter { alarm in
            (searchText.isEmpty || alarm.message.localizedCaseInsensitiveContains(searchText) ||
             alarm.source.localizedCaseInsensitiveContains(searchText)) &&
            (selectedSeverity.isEmpty || selectedSeverity.contains(alarm.severity))
        }
    }
    
    var filteredAcknowledgedAlarms: [Alarm] {
        alarmManager.acknowledgedAlarms.filter { alarm in
            (searchText.isEmpty || alarm.message.localizedCaseInsensitiveContains(searchText) ||
             alarm.source.localizedCaseInsensitiveContains(searchText)) &&
            (selectedSeverity.isEmpty || selectedSeverity.contains(alarm.severity))
        }
    }
    
    var filteredEvents: [SystemEvent] {
        alarmManager.events.filter { event in
            searchText.isEmpty || event.message.localizedCaseInsensitiveContains(searchText) ||
            event.source.localizedCaseInsensitiveContains(searchText)
        }
    }
}

struct AlarmSummaryIndicator: View {
    @ObservedObject var manager: AlarmEventManager
    
    var body: some View {
        HStack(spacing: OPCTheme.Spacing.lg) {
            ForEach(AlarmSeverity.allCases, id: \.self) { severity in
                let count = manager.activeAlarms.filter { $0.severity == severity }.count
                
                VStack(spacing: OPCTheme.Spacing.xs) {
                    HStack(spacing: OPCTheme.Spacing.xs) {
                        Circle()
                            .fill(severity.color)
                            .frame(width: 8, height: 8)
                            .if(count > 0 && severity == .critical) { view in
                                view.modifier(PulseAnimation(color: severity.color))
                            }
                        
                        Text(severity.shortName)
                            .font(OPCTheme.Typography.caption2)
                            .foregroundColor(OPCTheme.Colors.secondaryText)
                    }
                    
                    Text("\(count)")
                        .font(OPCTheme.Typography.headline)
                        .fontWeight(.bold)
                        .foregroundColor(count > 0 ? severity.color : OPCTheme.Colors.tertiaryText)
                }
            }
        }
        .padding(OPCTheme.Spacing.md)
        .modifier(GlassCard(cornerRadius: OPCTheme.Radius.md))
    }
}

struct AlarmListView: View {
    let alarms: [Alarm]
    let onAlarmTap: (Alarm) -> Void
    var onAcknowledge: ((Alarm) -> Void)? = nil
    var showAcknowledgeButton = true
    
    var body: some View {
        if alarms.isEmpty {
            emptyStateView
        } else {
            ScrollView {
                LazyVStack(spacing: OPCTheme.Spacing.sm) {
                    ForEach(alarms) { alarm in
                        AlarmRow(
                            alarm: alarm,
                            onTap: { onAlarmTap(alarm) },
                            onAcknowledge: showAcknowledgeButton ? {
                                onAcknowledge?(alarm)
                            } : nil
                        )
                    }
                }
                .padding()
            }
        }
    }
    
    var emptyStateView: some View {
        VStack(spacing: OPCTheme.Spacing.lg) {
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundColor(OPCTheme.Colors.tertiaryText)
            
            Text("No alarms")
                .font(OPCTheme.Typography.title3)
                .foregroundColor(OPCTheme.Colors.text)
            
            Text("All systems are running normally")
                .font(OPCTheme.Typography.body)
                .foregroundColor(OPCTheme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct AlarmRow: View {
    let alarm: Alarm
    let onTap: () -> Void
    let onAcknowledge: (() -> Void)?
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: OPCTheme.Spacing.md) {
                // Severity Indicator
                VStack {
                    Circle()
                        .fill(alarm.severity.color)
                        .frame(width: 12, height: 12)
                        .if(alarm.severity == .critical && alarm.state == .active) { view in
                            view.modifier(PulseAnimation(color: alarm.severity.color))
                        }
                    
                    if alarm.state == .active {
                        Rectangle()
                            .fill(alarm.severity.color.opacity(0.3))
                            .frame(width: 2)
                    }
                }
                
                VStack(alignment: .leading, spacing: OPCTheme.Spacing.xs) {
                    HStack {
                        Text(alarm.message)
                            .font(OPCTheme.Typography.callout)
                            .fontWeight(.medium)
                            .foregroundColor(OPCTheme.Colors.text)
                            .lineLimit(2)
                        
                        Spacer()
                        
                        Text(alarm.timestamp.formatted(.relative(presentation: .named)))
                            .font(OPCTheme.Typography.caption2)
                            .foregroundColor(OPCTheme.Colors.tertiaryText)
                    }
                    
                    HStack {
                        Text(alarm.source)
                            .font(OPCTheme.Typography.caption1)
                            .foregroundColor(OPCTheme.Colors.secondaryText)
                        
                        Spacer()
                        
                        HStack(spacing: OPCTheme.Spacing.xs) {
                            AlarmStateIndicator(state: alarm.state)
                            
                            Text(alarm.severity.rawValue)
                                .font(OPCTheme.Typography.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(alarm.severity.color)
                        }
                    }
                }
                
                if let onAcknowledge = onAcknowledge, alarm.state == .active {
                    Button(action: onAcknowledge) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 20))
                            .foregroundColor(OPCTheme.Colors.success)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(OPCTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                    .fill(alarm.state == .active ? 
                          alarm.severity.color.opacity(0.05) : 
                          OPCTheme.Colors.secondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                            .stroke(alarm.severity.color.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(OPCTheme.Animation.fast, value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity,
                          pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

struct AlarmStateIndicator: View {
    let state: AlarmState
    
    var body: some View {
        HStack(spacing: OPCTheme.Spacing.xs) {
            Image(systemName: state.icon)
                .font(.system(size: 10))
            Text(state.rawValue)
        }
        .font(OPCTheme.Typography.caption2)
        .foregroundColor(state.color)
        .padding(.horizontal, OPCTheme.Spacing.xs)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(state.color.opacity(0.1))
        )
    }
}

struct AlarmHistoryView: View {
    let alarms: [Alarm]
    let onAlarmTap: (Alarm) -> Void
    
    var groupedAlarms: [Date: [Alarm]] {
        Dictionary(grouping: alarms) { alarm in
            Calendar.current.startOfDay(for: alarm.timestamp)
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: OPCTheme.Spacing.lg) {
                ForEach(groupedAlarms.keys.sorted(by: >), id: \.self) { date in
                    VStack(alignment: .leading, spacing: OPCTheme.Spacing.sm) {
                        Text(date.formatted(.dateTime.weekday(.wide).month().day()))
                            .font(OPCTheme.Typography.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(OPCTheme.Colors.text)
                            .padding(.horizontal)
                        
                        ForEach(groupedAlarms[date] ?? []) { alarm in
                            AlarmRow(
                                alarm: alarm,
                                onTap: { onAlarmTap(alarm) },
                                onAcknowledge: nil
                            )
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }
}

struct EventListView: View {
    let events: [SystemEvent]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: OPCTheme.Spacing.sm) {
                ForEach(events) { event in
                    EventRow(event: event)
                }
            }
            .padding()
        }
    }
}

struct EventRow: View {
    let event: SystemEvent
    
    var body: some View {
        HStack(spacing: OPCTheme.Spacing.md) {
            Circle()
                .fill(event.type.color)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: OPCTheme.Spacing.xs) {
                HStack {
                    Text(event.message)
                        .font(OPCTheme.Typography.callout)
                        .foregroundColor(OPCTheme.Colors.text)
                    
                    Spacer()
                    
                    Text(event.timestamp.formatted(.dateTime.hour().minute().second()))
                        .font(OPCTheme.Typography.caption2)
                        .foregroundColor(OPCTheme.Colors.tertiaryText)
                }
                
                HStack {
                    Text(event.source)
                        .font(OPCTheme.Typography.caption1)
                        .foregroundColor(OPCTheme.Colors.secondaryText)
                    
                    Spacer()
                    
                    Text(event.type.rawValue)
                        .font(OPCTheme.Typography.caption2)
                        .foregroundColor(event.type.color)
                        .padding(.horizontal, OPCTheme.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(event.type.color.opacity(0.1))
                        )
                }
            }
        }
        .padding(OPCTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                .fill(OPCTheme.Colors.secondaryBackground)
        )
    }
}

struct AlarmDetailView: View {
    let alarm: Alarm
    @ObservedObject var manager: AlarmEventManager
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledgmentNote = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: OPCTheme.Spacing.lg) {
                    // Header
                    VStack(alignment: .leading, spacing: OPCTheme.Spacing.md) {
                        HStack {
                            Circle()
                                .fill(alarm.severity.color)
                                .frame(width: 16, height: 16)
                            
                            Text(alarm.severity.rawValue)
                                .font(OPCTheme.Typography.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(alarm.severity.color)
                            
                            Spacer()
                            
                            AlarmStateIndicator(state: alarm.state)
                        }
                        
                        Text(alarm.message)
                            .font(OPCTheme.Typography.title2)
                            .fontWeight(.bold)
                            .foregroundColor(OPCTheme.Colors.text)
                    }
                    .padding()
                    .modifier(GlassCard(cornerRadius: OPCTheme.Radius.lg))
                    
                    // Details
                    VStack(alignment: .leading, spacing: OPCTheme.Spacing.md) {
                        Text("Details")
                            .font(OPCTheme.Typography.headline)
                            .foregroundColor(OPCTheme.Colors.text)
                        
                        Grid(alignment: .leading, horizontalSpacing: OPCTheme.Spacing.xl, verticalSpacing: OPCTheme.Spacing.md) {
                            GridRow {
                                Text("Source:")
                                    .foregroundColor(OPCTheme.Colors.secondaryText)
                                Text(alarm.source)
                                    .fontWeight(.medium)
                            }
                            
                            GridRow {
                                Text("Node ID:")
                                    .foregroundColor(OPCTheme.Colors.secondaryText)
                                Text(alarm.nodeId ?? "N/A")
                                    .font(OPCTheme.Typography.monospacedSmall)
                                    .fontWeight(.medium)
                            }
                            
                            GridRow {
                                Text("Timestamp:")
                                    .foregroundColor(OPCTheme.Colors.secondaryText)
                                Text(alarm.timestamp.formatted(.dateTime.day().month().year().hour().minute().second()))
                                    .fontWeight(.medium)
                            }
                            
                            if let acknowledgedBy = alarm.acknowledgedBy {
                                GridRow {
                                    Text("Acknowledged by:")
                                        .foregroundColor(OPCTheme.Colors.secondaryText)
                                    Text(acknowledgedBy)
                                        .fontWeight(.medium)
                                }
                            }
                            
                            if let acknowledgedAt = alarm.acknowledgedAt {
                                GridRow {
                                    Text("Acknowledged at:")
                                        .foregroundColor(OPCTheme.Colors.secondaryText)
                                    Text(acknowledgedAt.formatted(.dateTime.day().month().year().hour().minute().second()))
                                        .fontWeight(.medium)
                                }
                            }
                        }
                        .font(OPCTheme.Typography.callout)
                    }
                    .padding()
                    .modifier(GlassCard(cornerRadius: OPCTheme.Radius.lg))
                    
                    // Actions
                    if alarm.state == .active {
                        VStack(alignment: .leading, spacing: OPCTheme.Spacing.md) {
                            Text("Acknowledge Alarm")
                                .font(OPCTheme.Typography.headline)
                                .foregroundColor(OPCTheme.Colors.text)
                            
                            TextField("Optional note...", text: $acknowledgmentNote, axis: .vertical)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            ModernButton(
                                title: "Acknowledge",
                                icon: "checkmark.circle",
                                style: .success
                            ) {
                                manager.acknowledgeAlarm(alarm, note: acknowledgmentNote)
                                dismiss()
                            }
                        }
                        .padding()
                        .modifier(GlassCard(cornerRadius: OPCTheme.Radius.lg))
                    }
                    
                    // Related Events
                    if !alarm.relatedEvents.isEmpty {
                        VStack(alignment: .leading, spacing: OPCTheme.Spacing.md) {
                            Text("Related Events (\(alarm.relatedEvents.count))")
                                .font(OPCTheme.Typography.headline)
                                .foregroundColor(OPCTheme.Colors.text)
                            
                            ForEach(alarm.relatedEvents.prefix(5), id: \.self) { eventId in
                                if let event = manager.events.first(where: { $0.id == eventId }) {
                                    EventRow(event: event)
                                }
                            }
                        }
                        .padding()
                        .modifier(GlassCard(cornerRadius: OPCTheme.Radius.lg))
                    }
                }
                .padding()
            }
            .navigationTitle("Alarm Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct AlarmSettingsView: View {
    @ObservedObject var manager: AlarmEventManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Notifications") {
                    Toggle("Enable Push Notifications", isOn: $manager.settings.notificationsEnabled)
                    Toggle("Sound Alerts", isOn: $manager.settings.soundEnabled)
                    Toggle("Vibrate on Critical Alarms", isOn: $manager.settings.vibrationEnabled)
                }
                
                Section("Auto-Acknowledgment") {
                    Toggle("Auto-acknowledge resolved alarms", isOn: $manager.settings.autoAcknowledge)
                    
                    if manager.settings.autoAcknowledge {
                        Stepper("After \(manager.settings.autoAcknowledgeDelay) seconds",
                                value: $manager.settings.autoAcknowledgeDelay,
                                in: 5...300,
                                step: 5)
                    }
                }
                
                Section("Retention") {
                    Picker("Keep alarm history for", selection: $manager.settings.historyRetentionDays) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("1 year").tag(365)
                    }
                    
                    Picker("Keep events for", selection: $manager.settings.eventRetentionDays) {
                        Text("1 day").tag(1)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                    }
                }
            }
            .navigationTitle("Alarm Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        manager.saveSettings()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Data Models

struct Alarm: Identifiable, Codable {
    var id: UUID
    let message: String
    let severity: AlarmSeverity
    let source: String
    let nodeId: String?
    let timestamp: Date
    var state: AlarmState
    var acknowledgedBy: String?
    var acknowledgedAt: Date?
    var acknowledgedNote: String?
    var relatedEvents: [UUID] = []

    init(
        id: UUID = UUID(),
        message: String,
        severity: AlarmSeverity,
        source: String,
        nodeId: String? = nil,
        timestamp: Date = Date(),
        state: AlarmState = .active
    ) {
        self.id = id
        self.message = message
        self.severity = severity
        self.source = source
        self.nodeId = nodeId
        self.timestamp = timestamp
        self.state = state
    }
}

enum AlarmSeverity: String, CaseIterable, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"
    
    var color: Color {
        switch self {
        case .low: return OPCTheme.Colors.info
        case .medium: return OPCTheme.Colors.warning
        case .high: return Color.orange
        case .critical: return OPCTheme.Colors.error
        }
    }
    
    var shortName: String {
        switch self {
        case .low: return "LOW"
        case .medium: return "MED"
        case .high: return "HIGH"
        case .critical: return "CRIT"
        }
    }
}

enum AlarmState: String, Codable {
    case active = "Active"
    case acknowledged = "Acknowledged"
    case resolved = "Resolved"
    
    var icon: String {
        switch self {
        case .active: return "exclamationmark.circle.fill"
        case .acknowledged: return "checkmark.circle"
        case .resolved: return "checkmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .active: return OPCTheme.Colors.error
        case .acknowledged: return OPCTheme.Colors.warning
        case .resolved: return OPCTheme.Colors.success
        }
    }
}

struct SystemEvent: Identifiable, Codable {
    var id: UUID
    let message: String
    let type: EventType
    let source: String
    let timestamp: Date
    let data: [String: String]?

    init(
        id: UUID = UUID(),
        message: String,
        type: EventType,
        source: String,
        data: [String: String]? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.message = message
        self.type = type
        self.source = source
        self.timestamp = timestamp
        self.data = data
    }
}

enum EventType: String, CaseIterable, Codable {
    case connection = "Connection"
    case subscription = "Subscription"
    case dataChange = "Data Change"
    case system = "System"
    case user = "User Action"
    
    var color: Color {
        switch self {
        case .connection: return OPCTheme.Colors.info
        case .subscription: return OPCTheme.Colors.success
        case .dataChange: return Color.blue
        case .system: return Color.gray
        case .user: return OPCTheme.Colors.primary
        }
    }
}

struct AlarmSettings: Codable {
    var notificationsEnabled = true
    var soundEnabled = true
    var vibrationEnabled = true
    var autoAcknowledge = false
    var autoAcknowledgeDelay = 30
    var historyRetentionDays = 30
    var eventRetentionDays = 7
}

class AlarmEventManager: ObservableObject {
    static let shared = AlarmEventManager()
    @Published var activeAlarms: [Alarm] = []
    @Published var acknowledgedAlarms: [Alarm] = []
    @Published var alarmHistory: [Alarm] = []
    @Published var events: [SystemEvent] = []
    @Published var settings = AlarmSettings()
    
    private let settingsKey = "alarm_settings"
    
    private init() {
        loadSettings()
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    func addAlarm(_ alarm: Alarm) {
        activeAlarms.append(alarm)
        
        if settings.notificationsEnabled {
            sendNotification(for: alarm)
        }
        
        logEvent(SystemEvent(
            message: "Alarm raised: \(alarm.message)",
            type: .system,
            source: alarm.source
        ))
    }
    
    func acknowledgeAlarm(_ alarm: Alarm, note: String = "") {
        guard let index = activeAlarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        
        var updatedAlarm = activeAlarms[index]
        updatedAlarm.state = .acknowledged
        updatedAlarm.acknowledgedBy = "Current User" // In real app, get from user session
        updatedAlarm.acknowledgedAt = Date()
        updatedAlarm.acknowledgedNote = note.isEmpty ? nil : note
        
        activeAlarms.remove(at: index)
        acknowledgedAlarms.append(updatedAlarm)
        alarmHistory.append(updatedAlarm)
        
        logEvent(SystemEvent(
            message: "Alarm acknowledged: \(alarm.message)",
            type: .user,
            source: alarm.source
        ))
    }
    
    func resolveAlarm(_ alarm: Alarm) {
        if let index = activeAlarms.firstIndex(where: { $0.id == alarm.id }) {
            var resolvedAlarm = activeAlarms[index]
            resolvedAlarm.state = .resolved
            activeAlarms.remove(at: index)
            alarmHistory.append(resolvedAlarm)
        } else if let index = acknowledgedAlarms.firstIndex(where: { $0.id == alarm.id }) {
            var resolvedAlarm = acknowledgedAlarms[index]
            resolvedAlarm.state = .resolved
            acknowledgedAlarms.remove(at: index)
            alarmHistory.append(resolvedAlarm)
        }
        
        logEvent(SystemEvent(
            message: "Alarm resolved: \(alarm.message)",
            type: .system,
            source: alarm.source
        ))
    }
    
    func logEvent(_ event: SystemEvent) {
        events.insert(event, at: 0)
        
        // Keep events within retention limit
        let retentionCutoff = Date().addingTimeInterval(-Double(settings.eventRetentionDays * 24 * 3600))
        events.removeAll { $0.timestamp < retentionCutoff }
    }
    
    func clearHistory() {
        alarmHistory.removeAll()
        events.removeAll()
    }
    
    func exportAlarmLog() {
        // Implementation for exporting alarm log
    }
    
    func saveSettings() {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: settingsKey)
        }
    }
    
    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AlarmSettings.self, from: data) {
            settings = decoded
        }
    }
    
    private func sendNotification(for alarm: Alarm) {
        let content = UNMutableNotificationContent()
        content.title = "OPC UA Alarm"
        content.body = "\(alarm.severity.rawValue): \(alarm.message)"
        content.sound = settings.soundEnabled ? .default : nil
        
        let request = UNNotificationRequest(
            identifier: alarm.id.uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func generateSampleData() {}
}
