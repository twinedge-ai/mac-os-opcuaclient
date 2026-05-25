import SwiftUI

/// View to display validation errors for monitored items
struct ValidationErrorView: View {
    let validation: MonitoredItemValidation
    @State private var showDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Error Header
            HStack {
                Image(systemName: iconForSeverity)
                    .foregroundColor(colorForSeverity)
                    .font(.system(size: 20))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(validation.savedDisplayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(validation.nodeId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { showDetails.toggle() }) {
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColorForSeverity.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(colorForSeverity.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(8)
            
            // Error Details (expandable)
            if showDetails {
                VStack(alignment: .leading, spacing: 6) {
                    if let issue = validation.issue {
                        Label {
                            Text(issue.description)
                                .font(.system(size: 13))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(colorForSeverity)
                                .font(.system(size: 12))
                        }
                    }
                    
                    HStack(spacing: 4) {
                        Text("Expected:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(validation.savedDisplayName)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    if let serverName = validation.serverDisplayName {
                        HStack(spacing: 4) {
                            Text("Server reports:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(serverName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                        }
                    }
                    
                    if let savedType = validation.savedDataType,
                       let serverType = validation.serverDataType,
                       savedType != serverType {
                        HStack(spacing: 4) {
                            Text("Type mismatch:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(savedType) → \(serverType)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    // Recommended Action
                    Divider()
                        .padding(.vertical, 4)
                    
                    Label {
                        Text(recommendedAction)
                            .font(.caption)
                            .foregroundColor(.primary)
                    } icon: {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 12))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
    }
    
    private var iconForSeverity: String {
        guard let severity = validation.issue?.severity else { return "checkmark.circle" }
        switch severity {
        case .critical:
            return "xmark.octagon.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .warning:
            return "exclamationmark.circle.fill"
        }
    }
    
    private var colorForSeverity: Color {
        guard let severity = validation.issue?.severity else { return .green }
        switch severity {
        case .critical:
            return .red
        case .error:
            return .orange
        case .warning:
            return .yellow
        }
    }
    
    private var backgroundColorForSeverity: Color {
        guard let severity = validation.issue?.severity else { return .green }
        switch severity {
        case .critical:
            return .red
        case .error:
            return .orange
        case .warning:
            return .yellow
        }
    }
    
    private var recommendedAction: String {
        guard let issue = validation.issue else { return "No action needed" }
        switch issue {
        case .nodeNotFound:
            return "Remove this item from the subscription or verify the server configuration"
        case .displayNameMismatch:
            return "Update the subscription or confirm if the server's node configuration has changed"
        case .dataTypeMismatch:
            return "Recreate the subscription with the correct node or verify server changes"
        case .nodeNotAccessible:
            return "Check server permissions or wait for the node to become available"
        }
    }
}

/// Alert banner for subscription validation issues
struct SubscriptionValidationAlert: View {
    let validationIssues: [MonitoredItemValidation]
    @State private var showingDetails = false
    
    var body: some View {
        if !validationIssues.isEmpty {
            VStack(spacing: 0) {
                // Alert Banner
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Subscription Validation Issues")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("\(validationIssues.count) item(s) have problems that need attention")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: { showingDetails.toggle() }) {
                        Text(showingDetails ? "Hide" : "Details")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(6)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.05))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.orange.opacity(0.2)),
                    alignment: .bottom
                )
                
                // Detailed Issues (expandable)
                if showingDetails {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(validationIssues, id: \.nodeId) { validation in
                                ValidationErrorView(validation: validation)
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 300)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .background(Color.controlBackgroundColor)
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .padding(.horizontal)
            .padding(.top, 8)
            .animation(.easeInOut, value: showingDetails)
        }
    }
}

/// Inline validation indicator for monitored items
struct ValidationIndicator: View {
    let validation: MonitoredItemValidation?
    
    var body: some View {
        if let validation = validation, !validation.isValid {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .font(.system(size: 12))
                
                if let issue = validation.issue {
                    Text(shortDescription(for: issue))
                        .font(.caption2)
                        .foregroundColor(iconColor)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(iconColor.opacity(0.1))
            .cornerRadius(4)
        }
    }
    
    private var iconName: String {
        guard let severity = validation?.issue?.severity else { return "info.circle" }
        switch severity {
        case .critical:
            return "xmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .warning:
            return "exclamationmark.circle"
        }
    }
    
    private var iconColor: Color {
        guard let severity = validation?.issue?.severity else { return .blue }
        switch severity {
        case .critical:
            return .red
        case .error:
            return .orange
        case .warning:
            return .yellow
        }
    }
    
    private func shortDescription(for issue: MonitoredItemValidation.ValidationIssue) -> String {
        switch issue {
        case .nodeNotFound:
            return "Not found"
        case .displayNameMismatch:
            return "Name mismatch"
        case .dataTypeMismatch:
            return "Type changed"
        case .nodeNotAccessible:
            return "Not accessible"
        }
    }
}