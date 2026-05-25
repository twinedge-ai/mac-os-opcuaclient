#include <stdio.h>
#include <stdlib.h>
#include <open62541/client.h>
#include <open62541/client_config_default.h>
#include <open62541/client_highlevel.h>

int main() {
    printf("=== VERIFYING NODE IDs ===\n\n");
    
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
    
    printf("YOUR SAVED SUBSCRIPTION HAS:\n");
    printf("=============================\n");
    
    // Node that's in the saved subscription (based on logs)
    printf("1. ns=2;i=187 (saved as 'Voltage'):\n");
    UA_NodeId node187 = UA_NODEID_NUMERIC(2, 187);
    
    // Get display name
    UA_LocalizedText displayName187;
    UA_LocalizedText_init(&displayName187);
    if(UA_Client_readDisplayNameAttribute(client, node187, &displayName187) == UA_STATUSCODE_GOOD) {
        printf("   Actual name: %.*s\n", (int)displayName187.text.length, displayName187.text.data);
    }
    UA_LocalizedText_clear(&displayName187);
    
    // Get value and type
    UA_Variant value187;
    UA_Variant_init(&value187);
    if(UA_Client_readValueAttribute(client, node187, &value187) == UA_STATUSCODE_GOOD) {
        if(value187.type) {
            printf("   Type: %s (ID=%d)\n", value187.type->typeName, value187.type->typeId.identifier.numeric);
            if(UA_Variant_hasScalarType(&value187, &UA_TYPES[UA_TYPES_STRING])) {
                UA_String* str = (UA_String*)value187.data;
                printf("   Value: '%.*s'\n", (int)str->length, str->data);
            } else if(UA_Variant_hasScalarType(&value187, &UA_TYPES[UA_TYPES_DOUBLE])) {
                printf("   Value: %.6f\n", *(UA_Double*)value187.data);
            }
        }
    }
    UA_Variant_clear(&value187);
    
    printf("\n2. ns=2;i=202 (saved as 'MotorWindingTemp'):\n");
    UA_NodeId node202 = UA_NODEID_NUMERIC(2, 202);
    
    // Get display name
    UA_LocalizedText displayName202;
    UA_LocalizedText_init(&displayName202);
    if(UA_Client_readDisplayNameAttribute(client, node202, &displayName202) == UA_STATUSCODE_GOOD) {
        printf("   Actual name: %.*s\n", (int)displayName202.text.length, displayName202.text.data);
    }
    UA_LocalizedText_clear(&displayName202);
    
    // Get value and type
    UA_Variant value202;
    UA_Variant_init(&value202);
    if(UA_Client_readValueAttribute(client, node202, &value202) == UA_STATUSCODE_GOOD) {
        if(value202.type) {
            printf("   Type: %s (ID=%d)\n", value202.type->typeName, value202.type->typeId.identifier.numeric);
            if(UA_Variant_hasScalarType(&value202, &UA_TYPES[UA_TYPES_DOUBLE])) {
                printf("   Value: %.6f\n", *(UA_Double*)value202.data);
            }
        }
    }
    UA_Variant_clear(&value202);
    
    printf("\n\nACTUAL VOLTAGE NODES ON SERVER:\n");
    printf("================================\n");
    
    // Check actual Voltage nodes we found
    int voltageNodes[] = {874, 931, 1000, 1057};
    const char* pumpNames[] = {"Pump 1", "Pump 2", "Pump 3", "Pump 4"};
    
    for(int i = 0; i < 4; i++) {
        printf("%d. ns=2;i=%d (%s Voltage):\n", i+1, voltageNodes[i], pumpNames[i]);
        
        UA_NodeId voltNode = UA_NODEID_NUMERIC(2, voltageNodes[i]);
        
        // Get display name
        UA_LocalizedText voltName;
        UA_LocalizedText_init(&voltName);
        if(UA_Client_readDisplayNameAttribute(client, voltNode, &voltName) == UA_STATUSCODE_GOOD) {
            printf("   Display name: %.*s\n", (int)voltName.text.length, voltName.text.data);
        }
        UA_LocalizedText_clear(&voltName);
        
        // Get value and type
        UA_Variant voltValue;
        UA_Variant_init(&voltValue);
        if(UA_Client_readValueAttribute(client, voltNode, &voltValue) == UA_STATUSCODE_GOOD) {
            if(voltValue.type) {
                printf("   Type: %s (ID=%d)\n", voltValue.type->typeName, voltValue.type->typeId.identifier.numeric);
                if(UA_Variant_hasScalarType(&voltValue, &UA_TYPES[UA_TYPES_DOUBLE])) {
                    printf("   Value: %.6f\n", *(UA_Double*)voltValue.data);
                }
            }
        }
        UA_Variant_clear(&voltValue);
    }
    
    printf("\n\nCONCLUSION:\n");
    printf("===========\n");
    printf("❌ Your saved subscription has node ns=2;i=187 which is 'Manufacturer' (STRING type)\n");
    printf("✅ You should use one of these Voltage nodes instead:\n");
    printf("   - ns=2;i=874 (Pump 1 Voltage - DOUBLE type)\n");
    printf("   - ns=2;i=931 (Pump 2 Voltage - DOUBLE type)\n");
    printf("   - ns=2;i=1000 (Pump 3 Voltage - DOUBLE type)\n");
    printf("   - ns=2;i=1057 (Pump 4 Voltage - DOUBLE type)\n");
    
    UA_Client_disconnect(client);
    UA_Client_delete(client);
    
    return 0;
}
