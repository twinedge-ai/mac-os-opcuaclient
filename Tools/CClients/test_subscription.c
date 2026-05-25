#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <open62541/client.h>
#include <open62541/client_config_default.h>
#include <open62541/client_highlevel.h>
#include <open62541/client_subscriptions.h>

static void dataChangeHandler(UA_Client *client, UA_UInt32 subId, void *subContext,
                             UA_UInt32 monId, void *monContext, UA_DataValue *value) {
    const char* nodeId = (const char*)monContext;
    
    printf("📊 Data change for %s:\n", nodeId);
    printf("  Status: %s\n", UA_StatusCode_name(value->status));
    
    if(value->hasValue && UA_Variant_isScalar(&value->value)) {
        UA_Variant *v = &value->value;
        printf("  Has data: YES\n");
        printf("  Is scalar: %s\n", UA_Variant_isScalar(v) ? "YES" : "NO");
        
        if(v->type) {
            printf("  Type ID: %u\n", v->type->typeId.identifier.numeric);
            printf("  Type: %s\n", v->type->typeName);
            
            if(UA_Variant_hasScalarType(v, &UA_TYPES[UA_TYPES_DOUBLE])) {
                printf("  Value (Double): %.6f\n", *(UA_Double*)v->data);
            } else if(UA_Variant_hasScalarType(v, &UA_TYPES[UA_TYPES_FLOAT])) {
                printf("  Value (Float): %.6f\n", *(UA_Float*)v->data);
            } else if(UA_Variant_hasScalarType(v, &UA_TYPES[UA_TYPES_STRING])) {
                UA_String* str = (UA_String*)v->data;
                if(str->length > 0) {
                    printf("  Value (String): '%.*s' (length: %d)\n", (int)str->length, str->data, (int)str->length);
                } else {
                    printf("  Value (String): '' (empty string, length: 0)\n");
                }
            } else {
                printf("  Value: [Unknown type]\n");
            }
        } else {
            printf("  Type: NULL\n");
        }
    } else {
        printf("  Has data: NO\n");
    }
    printf("\n");
}

int main() {
    printf("=== Testing OPC UA Subscriptions ===\n\n");
    
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
        printf("Failed to create subscription: %s\n", 
               UA_StatusCode_name(response.responseHeader.serviceResult));
        UA_Client_disconnect(client);
        UA_Client_delete(client);
        return 1;
    }
    
    UA_UInt32 subId = response.subscriptionId;
    printf("Created subscription ID: %u\n\n", subId);
    
    // Monitor Voltage
    UA_NodeId voltageNode = UA_NODEID_NUMERIC(2, 187);
    UA_MonitoredItemCreateRequest monRequest1 = 
        UA_MonitoredItemCreateRequest_default(voltageNode);
    monRequest1.requestedParameters.samplingInterval = 500.0;
    
    UA_MonitoredItemCreateResult monResponse1 = UA_Client_MonitoredItems_createDataChange(
        client, subId,
        UA_TIMESTAMPSTORETURN_BOTH,
        monRequest1, (void*)"ns=2;i=187", dataChangeHandler, NULL);
    
    printf("Monitoring Voltage (ns=2;i=187): %s (ID: %u)\n", 
           UA_StatusCode_name(monResponse1.statusCode), monResponse1.monitoredItemId);
    
    // Monitor Temperature
    UA_NodeId tempNode = UA_NODEID_NUMERIC(2, 202);
    UA_MonitoredItemCreateRequest monRequest2 = 
        UA_MonitoredItemCreateRequest_default(tempNode);
    monRequest2.requestedParameters.samplingInterval = 500.0;
    
    UA_MonitoredItemCreateResult monResponse2 = UA_Client_MonitoredItems_createDataChange(
        client, subId,
        UA_TIMESTAMPSTORETURN_BOTH,
        monRequest2, (void*)"ns=2;i=202", dataChangeHandler, NULL);
    
    printf("Monitoring Temperature (ns=2;i=202): %s (ID: %u)\n\n", 
           UA_StatusCode_name(monResponse2.statusCode), monResponse2.monitoredItemId);
    
    printf("Waiting for data changes (10 seconds)...\n\n");
    
    // Process subscriptions
    for(int i = 0; i < 10; i++) {
        UA_Client_run_iterate(client, 1000);
        sleep(1);
    }
    
    // Cleanup
    UA_Client_Subscriptions_deleteSingle(client, subId);
    UA_Client_disconnect(client);
    UA_Client_delete(client);
    
    return 0;
}
