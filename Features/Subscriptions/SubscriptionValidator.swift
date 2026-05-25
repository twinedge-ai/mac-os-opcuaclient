import Foundation

/// Validation result for a monitored item
struct MonitoredItemValidation {
    let nodeId: String
    let savedDisplayName: String
    let serverDisplayName: String?
    let savedDataType: String?
    let serverDataType: String?
    let isValid: Bool
    let issue: ValidationIssue?
    
    enum ValidationIssue {
        case nodeNotFound
        case displayNameMismatch
        case dataTypeMismatch
        case nodeNotAccessible
        
        var description: String {
            switch self {
            case .nodeNotFound:
                return "Node does not exist on server"
            case .displayNameMismatch:
                return "Display name has changed on server"
            case .dataTypeMismatch:
                return "Data type has changed on server"
            case .nodeNotAccessible:
                return "Node exists but cannot be read"
            }
        }
        
        var severity: Severity {
            switch self {
            case .nodeNotFound, .nodeNotAccessible:
                return .critical
            case .displayNameMismatch:
                return .warning
            case .dataTypeMismatch:
                return .error
            }
        }
        
        enum Severity {
            case warning    // Can continue but user should know
            case error      // Should fix but can try
            case critical   // Cannot continue
        }
    }
}

/// Validates subscriptions against the actual server state
class SubscriptionValidator {
    
    /// Validate a monitored item against the server
    static func validateMonitoredItem(
        _ item: MonitoredItem,
        client: SimpleOpcUaClient
    ) -> MonitoredItemValidation {
        
        // Try to browse the node to get its current display name
        let nodeInfo = client.browseNode(nodeId: item.nodeId).first
        
        // If node doesn't exist
        guard let nodeInfo = nodeInfo else {
            return MonitoredItemValidation(
                nodeId: item.nodeId,
                savedDisplayName: item.displayName,
                serverDisplayName: nil,
                savedDataType: nil,
                serverDataType: nil,
                isValid: false,
                issue: .nodeNotFound
            )
        }
        
        // Check if display names match (case-insensitive)
        let displayNameMatches = nodeInfo.displayName.lowercased() == item.displayName.lowercased()
        
        // Try to read the value to get data type
        let value = client.readValue(nodeId: item.nodeId)
        let dataType = client.readDataType(nodeId: item.nodeId)
        
        // Determine if there's an issue
        var issue: MonitoredItemValidation.ValidationIssue? = nil
        var isValid = true
        
        if !displayNameMatches {
            issue = .displayNameMismatch
            isValid = false // Mark as invalid if names don't match
        }
        
        // If we have a saved data type, check if it matches
        if let expectedType = getExpectedDataType(for: item.displayName),
           let actualType = dataType {
            if !isCompatibleDataType(expected: expectedType, actual: actualType) {
                issue = .dataTypeMismatch
                isValid = false
            }
        }
        
        // If value is nil but node exists, it might not be accessible
        if value == nil && issue == nil {
            issue = .nodeNotAccessible
            isValid = false
        }
        
        return MonitoredItemValidation(
            nodeId: item.nodeId,
            savedDisplayName: item.displayName,
            serverDisplayName: nodeInfo.displayName,
            savedDataType: getExpectedDataType(for: item.displayName),
            serverDataType: dataType,
            isValid: isValid,
            issue: issue
        )
    }
    
    /// Validate all items in a subscription
    static func validateSubscription(
        _ subscription: Subscription,
        client: SimpleOpcUaClient
    ) -> [MonitoredItemValidation] {
        
        return subscription.monitoredItems.map { item in
            validateMonitoredItem(item, client: client)
        }
    }
    
    /// Get expected data type based on common tag names
    private static func getExpectedDataType(for displayName: String) -> String? {
        let name = displayName.lowercased()
        
        // Common industrial tag patterns
        if name.contains("voltage") || 
           name.contains("current") || 
           name.contains("power") ||
           name.contains("temp") || 
           name.contains("pressure") ||
           name.contains("flow") || 
           name.contains("speed") ||
           name.contains("rpm") {
            return "Double"
        }
        
        if name.contains("status") || 
           name.contains("state") || 
           name.contains("alarm") ||
           name.contains("enable") || 
           name.contains("active") {
            return "Boolean"
        }
        
        if name.contains("name") || 
           name.contains("description") ||
           name.contains("manufacturer") || 
           name.contains("model") {
            return "String"
        }
        
        if name.contains("count") || 
           name.contains("index") {
            return "Integer"
        }
        
        return nil
    }
    
    /// Check if actual data type is compatible with expected
    private static func isCompatibleDataType(expected: String, actual: String) -> Bool {
        // Handle type variations
        let numericTypes = ["Double", "Float", "Real", "Single"]
        let integerTypes = ["Int32", "UInt32", "Int16", "UInt16", "Integer", "Long", "Short"]
        let booleanTypes = ["Boolean", "Bool"]
        let stringTypes = ["String", "CharArray", "Text"]
        
        let expectedLower = expected.lowercased()
        let actualLower = actual.lowercased()
        
        // Direct match
        if expectedLower == actualLower {
            return true
        }
        
        // Check type families
        if expected == "Double" && numericTypes.contains(where: { actualLower.contains($0.lowercased()) }) {
            return true
        }
        
        if expected == "Integer" && integerTypes.contains(where: { actualLower.contains($0.lowercased()) }) {
            return true
        }
        
        if expected == "Boolean" && booleanTypes.contains(where: { actualLower.contains($0.lowercased()) }) {
            return true
        }
        
        if expected == "String" && stringTypes.contains(where: { actualLower.contains($0.lowercased()) }) {
            return true
        }
        
        return false
    }
    
    /// Generate a validation report for the user
    static func generateValidationReport(validations: [MonitoredItemValidation]) -> String {
        var report = "=== Subscription Validation Report ===\n\n"
        
        let issues = validations.filter { !$0.isValid }
        
        if issues.isEmpty {
            report += "✅ All monitored items are valid\n"
        } else {
            report += "⚠️ Found \(issues.count) issue(s):\n\n"
            
            for validation in issues {
                report += "Node: \(validation.nodeId)\n"
                report += "  Saved Name: \(validation.savedDisplayName)\n"
                if let serverName = validation.serverDisplayName {
                    report += "  Server Name: \(serverName)\n"
                }
                if let issue = validation.issue {
                    report += "  Issue: \(issue.description)\n"
                    report += "  Severity: \(issue.severity)\n"
                }
                report += "\n"
            }
            
            report += "Recommended Actions:\n"
            
            let critical = issues.filter { $0.issue?.severity == .critical }
            if !critical.isEmpty {
                report += "• Remove nodes that no longer exist\n"
            }
            
            let nameChanges = issues.filter { $0.issue == .displayNameMismatch }
            if !nameChanges.isEmpty {
                report += "• Update display names or verify server configuration\n"
            }
            
            let typeChanges = issues.filter { $0.issue == .dataTypeMismatch }
            if !typeChanges.isEmpty {
                report += "• Review data type changes - may need new subscription\n"
            }
        }
        
        return report
    }
}
