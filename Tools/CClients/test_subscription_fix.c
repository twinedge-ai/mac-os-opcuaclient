#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "OpcUaWrapper.h"

// Test program to verify subscription restoration with proper data type handling
int main() {
    printf("=== Testing OPC UA Subscription Restoration Fix ===\n\n");
    
    // Create and connect client
    OpcUaClient_t* client = opcua_client_create();
    if (!client) {
        printf("❌ Failed to create client\n");
        return 1;
    }
    
    // Connect to local test server
    const char* endpoint = "opc.tcp://127.0.0.1:4840";
    printf("📡 Connecting to %s...\n", endpoint);
    
    if (!opcua_client_connect(client, endpoint)) {
        printf("❌ Failed to connect\n");
        opcua_client_destroy(client);
        return 1;
    }
    
    printf("✅ Connected successfully\n\n");
    
    // Test reading various node types
    printf("=== Testing Direct Value Reading ===\n");
    
    // Test node that was problematic (Voltage)
    const char* voltage_node = "ns=2;i=187";
    printf("\n1. Testing Voltage node (%s):\n", voltage_node);
    char* voltage_value = opcua_read_value_string(client, voltage_node);
    if (voltage_value) {
        printf("   ✅ Value: '%s'\n", voltage_value);
        opcua_free_string(voltage_value);
    } else {
        printf("   ⚠️ Value is NULL (not initialized yet)\n");
    }
    
    // Test node that worked (MotorWindingTemp)
    const char* temp_node = "ns=2;i=202";
    printf("\n2. Testing MotorWindingTemp node (%s):\n", temp_node);
    char* temp_value = opcua_read_value_string(client, temp_node);
    if (temp_value) {
        printf("   ✅ Value: '%s'\n", temp_value);
        opcua_free_string(temp_value);
    } else {
        printf("   ⚠️ Value is NULL\n");
    }
    
    // Test with subscription
    printf("\n=== Testing Subscription with Monitored Items ===\n");
    
    // Create subscription
    uint32_t sub_id = opcua_create_subscription(client, 1000.0);
    if (sub_id == 0) {
        printf("❌ Failed to create subscription\n");
        opcua_client_disconnect(client);
        opcua_client_destroy(client);
        return 1;
    }
    
    printf("✅ Created subscription ID: %u\n", sub_id);
    
    // Add monitored items
    uint32_t mon_id1 = opcua_add_monitored_item(client, sub_id, voltage_node, 1000.0);
    if (mon_id1 > 0) {
        printf("✅ Monitoring %s (ID: %u)\n", voltage_node, mon_id1);
    } else {
        printf("❌ Failed to monitor %s\n", voltage_node);
    }
    
    uint32_t mon_id2 = opcua_add_monitored_item(client, sub_id, temp_node, 1000.0);
    if (mon_id2 > 0) {
        printf("✅ Monitoring %s (ID: %u)\n", temp_node, mon_id2);
    } else {
        printf("❌ Failed to monitor %s\n", temp_node);
    }
    
    // Process subscriptions for a few seconds to see data changes
    printf("\n=== Waiting for Data Changes (5 seconds) ===\n");
    for (int i = 0; i < 5; i++) {
        opcua_process_subscriptions(client, 1000);
        
        // Check monitored values
        char* val1 = opcua_get_monitored_value(client, voltage_node);
        char* val2 = opcua_get_monitored_value(client, temp_node);
        
        printf("After %d sec - Voltage: %s, Temp: %s\n", 
               i + 1,
               val1 ? val1 : "[no data]",
               val2 ? val2 : "[no data]");
        
        if (val1) opcua_free_string(val1);
        if (val2) opcua_free_string(val2);
    }
    
    // Clean up
    printf("\n=== Cleanup ===\n");
    opcua_delete_subscription(client, sub_id);
    opcua_client_disconnect(client);
    opcua_client_destroy(client);
    
    printf("✅ Test completed\n");
    return 0;
}
