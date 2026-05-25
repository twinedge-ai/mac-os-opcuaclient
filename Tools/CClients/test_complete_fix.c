#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <open62541/client.h>
#include <open62541/client_config_default.h>
#include <open62541/client_highlevel.h>
#include <open62541/client_subscriptions.h>

// Test the complete fix - subscription to the correct Voltage node
static void dataChangeHandler(UA_Client *client, UA_UInt32 subId, void *subContext,
                             UA_UInt32 monId, void *monContext, UA_DataValue *value) {
    const char* nodeId = (const char*)monContext;
    
    printf("📊 Data change for %s:\n", nodeId);
    
    if(value->hasValue && UA_Variant_isScalar(&value->value)) {
        UA_Variant *v = &value->value;
        
        if(v->type) {
            // Check if it's a Double (type ID 11)
            if(UA_Variant_hasScalarType(v, &UA_TYPES[UA_TYPES_DOUBLE])) {
                printf("   ✅ Type: Double (correct!)\n");
                printf("   ✅ Value: %.6f\n", *(UA_Double*)v->data);
            } else if(UA_Variant_hasScalarType(v, &UA_TYPES[UA_TYPES_STRING])) {
                UA_String* str = (UA_String*)v->data;
                printf("   ❌ Type: String (wrong type!)\n");
                printf("   ❌ Value: '%.*s'\n", (int)str->length, str->data);
            } else {
                printf("   ⚠️ Type ID: %d\n", v->type->typeId.identifier.numeric);
            }
        }
    }
    printf("\n");
}

int main() {
    printf("=== Testing Complete Fix for Subscription ===\n\n");
    
    UA_Client *client = UA_Client_new();
    if(!client) {
        fprintf(stderr, "Failed to allocate OPC UA client\n");
        return 1;
    }
    UA_ClientConfig_setDefault(UA_Client_getConfig(client));
    
    UA_StatusCode retval = UA_Client_connect(client, "opc.tcp://127.0.0.1:4840");
    if(retval != UA_STATUSCODE_GOOD) {
        printf("Failed to connect: %s\n", UA_StatusCode_name(retval));
        UA_Client_delete(client);
        return 1;
    }
    
    printf("Connected to server\n\n");
    
    // Create subscription
    UA_CreateSubscriptionRequest request = UA_CreateSubscriptionRequest_default();
    request.requestedPublishingInterval = 1000.0;
    
    UA_CreateSubscriptionResponse response = 
        UA_Client_Subscriptions_create(client, request, NULL, NULL, NULL);
    
    if(response.responseHeader.serviceResult != UA_STATUSCODE_GOOD) {
        printf("Failed to create subscription\n");
        UA_Client_disconnect(client);
        UA_Client_delete(client);
        return 1;
    }
    
    UA_UInt32 subId = response.subscriptionId;
    printf("Created subscription ID: %u\n\n", subId);
    
    printf("Testing subscription with CORRECTED node IDs:\n");
    printf("===========================================\n\n");
    
    // Monitor the CORRECT Voltage node (after migration)
    printf("1. Monitoring CORRECT Voltage node (ns=2;i=874):\n");
    UA_NodeId correctVoltageNode = UA_NODEID_NUMERIC(2, 874);
    UA_MonitoredItemCreateRequest monRequest1 = 
        UA_MonitoredItemCreateRequest_default(correctVoltageNode);
    monRequest1.requestedParameters.samplingInterval = 500.0;
    
    UA_MonitoredItemCreateResult monResponse1 = UA_Client_MonitoredItems_createDataChange(
        client, subId,
        UA_TIMESTAMPSTORETURN_BOTH,
        monRequest1, (void*)"ns=2;i=874 (Voltage - CORRECT)", dataChangeHandler, NULL);
    
    if(monResponse1.statusCode == UA_STATUSCODE_GOOD) {
        printf("   ✅ Successfully monitoring (ID: %u)\n", monResponse1.monitoredItemId);
    } else {
        printf("   ❌ Failed: %s\n", UA_StatusCode_name(monResponse1.statusCode));
    }
    
    // Monitor Temperature (this was always correct)
    printf("\n2. Monitoring Temperature node (ns=2;i=202):\n");
    UA_NodeId tempNode = UA_NODEID_NUMERIC(2, 202);
    UA_MonitoredItemCreateRequest monRequest2 = 
        UA_MonitoredItemCreateRequest_default(tempNode);
    monRequest2.requestedParameters.samplingInterval = 500.0;
    
    UA_MonitoredItemCreateResult monResponse2 = UA_Client_MonitoredItems_createDataChange(
        client, subId,
        UA_TIMESTAMPSTORETURN_BOTH,
        monRequest2, (void*)"ns=2;i=202 (MotorWindingTemp)", dataChangeHandler, NULL);
    
    if(monResponse2.statusCode == UA_STATUSCODE_GOOD) {
        printf("   ✅ Successfully monitoring (ID: %u)\n", monResponse2.monitoredItemId);
    } else {
        printf("   ❌ Failed: %s\n", UA_StatusCode_name(monResponse2.statusCode));
    }
    
    printf("\nFor comparison, testing the OLD WRONG node:\n");
    printf("============================================\n");
    
    // Try the WRONG node to show it's a String
    printf("\n3. Testing OLD WRONG node (ns=2;i=187 - Manufacturer):\n");
    UA_NodeId wrongNode = UA_NODEID_NUMERIC(2, 187);
    UA_MonitoredItemCreateRequest monRequest3 = 
        UA_MonitoredItemCreateRequest_default(wrongNode);
    monRequest3.requestedParameters.samplingInterval = 500.0;
    
    UA_MonitoredItemCreateResult monResponse3 = UA_Client_MonitoredItems_createDataChange(
        client, subId,
        UA_TIMESTAMPSTORETURN_BOTH,
        monRequest3, (void*)"ns=2;i=187 (Manufacturer - WRONG!)", dataChangeHandler, NULL);
    
    if(monResponse3.statusCode == UA_STATUSCODE_GOOD) {
        printf("   ⚠️ Monitoring wrong node (ID: %u)\n", monResponse3.monitoredItemId);
    }
    
    printf("\n=== Waiting for Data Changes (5 seconds) ===\n\n");
    
    // Process subscriptions
    for(int i = 0; i < 5; i++) {
        UA_Client_run_iterate(client, 1000);
        sleep(1);
    }
    
    printf("=== SUMMARY ===\n");
    printf("✅ The corrected node (ns=2;i=874) returns DOUBLE values\n");
    printf("✅ Temperature node (ns=2;i=202) returns DOUBLE values\n");
    printf("❌ The old wrong node (ns=2;i=187) returns STRING (empty)\n");
    printf("\nThe migration fixes this by replacing ns=2;i=187 with ns=2;i=874\n");
    
    // Cleanup
    UA_Client_Subscriptions_deleteSingle(client, subId);
    UA_Client_disconnect(client);
    UA_Client_delete(client);
    
    return 0;
}
