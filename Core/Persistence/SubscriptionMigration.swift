import Foundation
import SwiftData

/// Migration to fix incorrect node IDs in saved subscriptions
@MainActor
class SubscriptionMigration {
    
    /// Known incorrect node mappings that need to be fixed
    private static let nodeIdCorrections: [String: (correctId: String, displayName: String)] = [
        "ns=2;i=187": ("ns=2;i=874", "Voltage"),  // Was "Manufacturer" (STRING), should be Voltage (DOUBLE)
    ]
    
    /// Migrate subscriptions to fix incorrect node IDs
    static func migrateSubscriptions(in modelContext: ModelContext) {
        print("🔍 [Migration] Starting subscription node ID migration...")
        print("   Checking for known incorrect node IDs:")
        for (wrongId, correction) in nodeIdCorrections {
            print("   - \(wrongId) → \(correction.correctId) (\(correction.displayName))")
        }
        
        do {
            // Fetch all monitored items
            let descriptor = FetchDescriptor<MonitoredItemModel>()
            let monitoredItems = try modelContext.fetch(descriptor)
            
            print("📊 [Migration] Found \(monitoredItems.count) monitored items to check")
            
            var migratedCount = 0
            
            for item in monitoredItems {
                // Check if this node ID needs correction
                if let correction = nodeIdCorrections[item.nodeId] {
                    print("🔧 [Migration] FIXING INCORRECT NODE:")
                    print("   ❌ OLD: \(item.nodeId) ('\(item.displayName)')")
                    print("   ✅ NEW: \(correction.correctId) ('\(correction.displayName)')")
                    
                    // Update the node ID and display name
                    item.nodeId = correction.correctId
                    item.displayName = correction.displayName
                    item.updatedAt = Date()
                    
                    migratedCount += 1
                } else {
                    print("   ✓ Node \(item.nodeId) ('\(item.displayName)') is correct")
                }
            }
            
            if migratedCount > 0 {
                // Save the changes
                try modelContext.save()
                print("✅ [Migration] Successfully fixed \(migratedCount) incorrect node ID(s)")
                print("   The subscription will now work correctly with DOUBLE values")
            } else {
                print("✅ [Migration] All node IDs are already correct - no fixes needed")
            }
            
        } catch {
            print("❌ [Migration] Failed to migrate subscriptions: \(error)")
        }
    }
    
    /// Check if a node ID is known to be incorrect
    static func isIncorrectNodeId(_ nodeId: String) -> Bool {
        return nodeIdCorrections[nodeId] != nil
    }
    
    /// Get the correct node ID for a known incorrect one
    static func getCorrectedNodeId(for nodeId: String) -> String? {
        return nodeIdCorrections[nodeId]?.correctId
    }
    
    /// Validate that a node ID returns the expected data type
    /// This can be called during subscription restoration to detect mismatches
    static func validateNodeDataType(nodeId: String, expectedType: String, actualType: String?) -> Bool {
        // For numeric nodes (voltages, temperatures, etc), we expect Double type
        if nodeId.contains("i=187") && actualType == "String" {
            // This is the known incorrect Manufacturer node
            return false
        }
        
        // Check if actual type matches expected
        if let actualType = actualType {
            // Map common OPC UA type names to expected values
            let typeMatches: [String: [String]] = [
                "Double": ["Double", "Float", "Real"],
                "String": ["String", "CharArray"],
                "Integer": ["Int32", "UInt32", "Int16", "UInt16", "Integer"],
                "Boolean": ["Boolean", "Bool"]
            ]
            
            if let acceptableTypes = typeMatches[expectedType] {
                return acceptableTypes.contains(actualType)
            }
        }
        
        return true // Default to valid if we can't determine
    }
}

// Extension to AppState to run migration on startup
extension AppState {
    func runSubscriptionMigrations() {
        Task { @MainActor in
            // Use the persistence manager to get model context
            if let modelContainer = try? ModelContainer(for: SubscriptionModel.self, MonitoredItemModel.self, ServerModel.self) {
                let modelContext = modelContainer.mainContext
                SubscriptionMigration.migrateSubscriptions(in: modelContext)
            }
        }
    }
}