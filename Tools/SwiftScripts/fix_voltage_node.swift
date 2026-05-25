#!/usr/bin/env swift

// Script to fix the wrong Voltage node ID in saved subscriptions
// The issue: ns=2;i=187 is a STRING type that's always empty
// The fix: Replace with ns=2;i=874 which is a DOUBLE type Voltage variable

import Foundation

// This script should be integrated into the app to fix saved subscriptions
// For now, it shows what needs to be done

print("=== Fix for Wrong Voltage Node ID ===")
print("")
print("PROBLEM IDENTIFIED:")
print("  • Node ns=2;i=187 is a STRING type variable that's always empty")
print("  • The actual Voltage variables are DOUBLE types at different node IDs:")
print("    - ns=2;i=874 (Pump 1 Voltage)")
print("    - ns=2;i=931 (Pump 2 Voltage)")
print("    - ns=2;i=1000 (Pump 3 Voltage)")
print("    - ns=2;i=1057 (Pump 4 Voltage)")
print("")
print("SOLUTION:")
print("  1. Delete the existing subscription with the wrong node ID")
print("  2. Create a new subscription with the correct node ID (e.g., ns=2;i=874)")
print("  3. Or update the saved MonitoredItemModel to use the correct nodeId")
print("")
print("TO FIX IN THE APP:")
print("  • Go to Subscriptions view")
print("  • Edit the subscription")
print("  • Remove the Voltage item with node ID ns=2;i=187")
print("  • Add a new Voltage item with node ID ns=2;i=874 (or another from the list above)")
print("")
print("ALTERNATIVE CODE FIX:")
print("  Add a migration in AppState or SubscriptionPersistenceManager to:")
print("  - Check for nodeId 'ns=2;i=187' in MonitoredItems")
print("  - Replace it with 'ns=2;i=874' (or prompt user to select correct one)")