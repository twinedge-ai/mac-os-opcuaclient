#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <open62541/client.h>
#include <open62541/client_config_default.h>
#include <open62541/client_highlevel.h>

// Direct test to see what's happening with node ns=2;i=187
int main() {
    printf("=== Direct OPC UA Read Test ===\n\n");
    
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
    
    // Test reading both nodes
    UA_NodeId voltageNode = UA_NODEID_NUMERIC(2, 187);
    UA_NodeId tempNode = UA_NODEID_NUMERIC(2, 202);
    
    // Read Voltage node
    printf("Reading Voltage node (ns=2;i=187):\n");
    UA_Variant voltageValue;
    UA_Variant_init(&voltageValue);
    
    retval = UA_Client_readValueAttribute(client, voltageNode, &voltageValue);
    printf("  Read status: %s (0x%08X)\n", UA_StatusCode_name(retval), retval);
    
    if(retval == UA_STATUSCODE_GOOD) {
        printf("  Has value: %s\n", voltageValue.data ? "YES" : "NO");
        printf("  Is scalar: %s\n", UA_Variant_isScalar(&voltageValue) ? "YES" : "NO");
        if(voltageValue.type) {
            printf("  Type ID: %u\n", voltageValue.type->typeId.identifier.numeric);
            printf("  Type name: %s\n", voltageValue.type->typeName);
            printf("  Memory size: %d\n", voltageValue.type->memSize);
            
            if(UA_Variant_hasScalarType(&voltageValue, &UA_TYPES[UA_TYPES_DOUBLE])) {
                printf("  Value (Double): %.6f\n", *(UA_Double*)voltageValue.data);
            } else if(UA_Variant_hasScalarType(&voltageValue, &UA_TYPES[UA_TYPES_FLOAT])) {
                printf("  Value (Float): %.6f\n", *(UA_Float*)voltageValue.data);
            } else if(UA_Variant_hasScalarType(&voltageValue, &UA_TYPES[UA_TYPES_INT32])) {
                printf("  Value (Int32): %d\n", *(UA_Int32*)voltageValue.data);
            } else if(UA_Variant_hasScalarType(&voltageValue, &UA_TYPES[UA_TYPES_STRING])) {
                UA_String *str = (UA_String*)voltageValue.data;
                printf("  Value (String): %.*s\n", (int)str->length, str->data);
            } else {
                printf("  Value: [Non-scalar or unknown type]\n");
            }
        } else {
            printf("  Type: NULL\n");
        }
    }
    
    UA_Variant_clear(&voltageValue);
    
    printf("\n");
    
    // Read Temperature node
    printf("Reading Temperature node (ns=2;i=202):\n");
    UA_Variant tempValue;
    UA_Variant_init(&tempValue);
    
    retval = UA_Client_readValueAttribute(client, tempNode, &tempValue);
    printf("  Read status: %s (0x%08X)\n", UA_StatusCode_name(retval), retval);
    
    if(retval == UA_STATUSCODE_GOOD) {
        printf("  Has value: %s\n", tempValue.data ? "YES" : "NO");
        printf("  Is scalar: %s\n", UA_Variant_isScalar(&tempValue) ? "YES" : "NO");
        if(tempValue.type) {
            printf("  Type ID: %u\n", tempValue.type->typeId.identifier.numeric);
            printf("  Type name: %s\n", tempValue.type->typeName);
            printf("  Memory size: %d\n", tempValue.type->memSize);
            
            if(UA_Variant_hasScalarType(&tempValue, &UA_TYPES[UA_TYPES_DOUBLE])) {
                printf("  Value (Double): %.6f\n", *(UA_Double*)tempValue.data);
            } else if(UA_Variant_hasScalarType(&tempValue, &UA_TYPES[UA_TYPES_FLOAT])) {
                printf("  Value (Float): %.6f\n", *(UA_Float*)tempValue.data);
            } else if(UA_Variant_hasScalarType(&tempValue, &UA_TYPES[UA_TYPES_INT32])) {
                printf("  Value (Int32): %d\n", *(UA_Int32*)tempValue.data);
            } else if(UA_Variant_hasScalarType(&tempValue, &UA_TYPES[UA_TYPES_STRING])) {
                UA_String *str = (UA_String*)tempValue.data;
                printf("  Value (String): %.*s\n", (int)str->length, str->data);
            } else {
                printf("  Value: [Non-scalar or unknown type]\n");
            }
        } else {
            printf("  Type: NULL\n");
        }
    }
    
    UA_Variant_clear(&tempValue);
    
    // Also check data types
    printf("\nChecking data type attributes:\n");
    
    UA_NodeId voltageDataType;
    UA_NodeId_init(&voltageDataType);
    retval = UA_Client_readDataTypeAttribute(client, voltageNode, &voltageDataType);
    if(retval == UA_STATUSCODE_GOOD) {
        printf("  Voltage data type: ns=%u;i=%u\n", voltageDataType.namespaceIndex, voltageDataType.identifier.numeric);
    }
    UA_NodeId_clear(&voltageDataType);
    
    UA_NodeId tempDataType;
    UA_NodeId_init(&tempDataType);
    retval = UA_Client_readDataTypeAttribute(client, tempNode, &tempDataType);
    if(retval == UA_STATUSCODE_GOOD) {
        printf("  Temperature data type: ns=%u;i=%u\n", tempDataType.namespaceIndex, tempDataType.identifier.numeric);
    }
    UA_NodeId_clear(&tempDataType);
    
    UA_Client_disconnect(client);
    UA_Client_delete(client);
    
    return 0;
}
