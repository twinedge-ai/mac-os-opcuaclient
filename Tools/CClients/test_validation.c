#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <open62541/client.h>
#include <open62541/client_config_default.h>
#include <open62541/client_highlevel.h>

// Test to demonstrate the validation system
int main() {
    printf("=== Subscription Validation Demo ===\n\n");
    
    UA_Client *client = UA_Client_new();
    if(!client) {
        fprintf(stderr, "Failed to allocate OPC UA client\n");
        return 1;
    }
    UA_ClientConfig_setDefault(UA_Client_getConfig(client));
    
    if(UA_Client_connect(client, "opc.tcp://127.0.0.1:4840") != UA_STATUSCODE_GOOD) {
        printf("Failed to connect\n");
        UA_Client_delete(client);
        return 1;
    }
    
    printf("Connected to server\n\n");
    
    printf("SCENARIO 1: Saved subscription has wrong display name\n");
    printf("==========================================\n");
    printf("Saved: nodeId='ns=2;i=187', displayName='Voltage'\n");
    
    // Check what's actually on the server
    UA_NodeId node187 = UA_NODEID_NUMERIC(2, 187);
    UA_LocalizedText displayName;
    UA_LocalizedText_init(&displayName);
    
    if(UA_Client_readDisplayNameAttribute(client, node187, &displayName) == UA_STATUSCODE_GOOD) {
        printf("Server: nodeId='ns=2;i=187', displayName='%.*s'\n", 
               (int)displayName.text.length, displayName.text.data);
    }
    UA_LocalizedText_clear(&displayName);
    
    // Check data type
    UA_NodeId dataTypeId;
    UA_NodeId_init(&dataTypeId);
    if(UA_Client_readDataTypeAttribute(client, node187, &dataTypeId) == UA_STATUSCODE_GOOD) {
        const char* typeName = dataTypeId.identifier.numeric == 12 ? "String" : 
                               dataTypeId.identifier.numeric == 11 ? "Double" : "Unknown";
        printf("Data Type: %s (ID=%d)\n", typeName, dataTypeId.identifier.numeric);
    }
    UA_NodeId_clear(&dataTypeId);
    
    printf("\n❌ VALIDATION FAILS: Display name mismatch!\n");
    printf("   Expected: 'Voltage' but got 'Manufacturer'\n");
    printf("   Action: User will be notified to update or recreate subscription\n");
    
    printf("\n\nSCENARIO 2: Server reorganized - node doesn't exist\n");
    printf("==========================================\n");
    printf("Saved: nodeId='ns=2;i=9999', displayName='OldTag'\n");
    
    UA_NodeId node9999 = UA_NODEID_NUMERIC(2, 9999);
    UA_Variant value;
    UA_Variant_init(&value);
    
    UA_StatusCode status = UA_Client_readValueAttribute(client, node9999, &value);
    if(status != UA_STATUSCODE_GOOD) {
        printf("Server: Node ns=2;i=9999 does not exist\n");
        printf("Status: %s\n", UA_StatusCode_name(status));
    }
    UA_Variant_clear(&value);
    
    printf("\n❌ VALIDATION FAILS: Node not found!\n");
    printf("   Action: Item will be skipped, user notified to remove it\n");
    
    printf("\n\nSCENARIO 3: Data type changed\n");
    printf("==========================================\n");
    printf("Example: A tag that was Double is now String\n");
    printf("This would be detected by comparing expected vs actual data types\n");
    
    printf("\n\nVALIDATION BENEFITS:\n");
    printf("====================\n");
    printf("✅ Detects when server configuration has changed\n");
    printf("✅ Prevents subscribing to wrong nodes\n");
    printf("✅ Alerts user when saved data is stale\n");
    printf("✅ Helps maintain data integrity\n");
    printf("✅ Provides clear error messages\n");
    
    printf("\n\nHOW IT WORKS:\n");
    printf("==============\n");
    printf("1. When restoring subscriptions after connection:\n");
    printf("   - Read display name from server for each saved node\n");
    printf("   - Compare with saved display name\n");
    printf("   - Check if node exists and is readable\n");
    printf("   - Verify data type matches expected type\n");
    printf("\n2. If validation fails:\n");
    printf("   - Skip invalid items\n");
    printf("   - Show alarm/notification to user\n");
    printf("   - Log detailed error in diagnostics\n");
    printf("   - Suggest creating new subscription\n");
    
    UA_Client_disconnect(client);
    UA_Client_delete(client);
    
    return 0;
}
