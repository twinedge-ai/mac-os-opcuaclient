#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <open62541/client.h>
#include <open62541/client_config_default.h>
#include <open62541/client_highlevel.h>

// Test to confirm the exact type of node ns=2;i=187
int main() {
    printf("=== Testing Exact Node ns=2;i=187 ===\n\n");
    
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
    
    UA_NodeId nodeId = UA_NODEID_NUMERIC(2, 187);
    
    // 1. Read the browse name
    UA_QualifiedName browseName;
    UA_QualifiedName_init(&browseName);
    retval = UA_Client_readBrowseNameAttribute(client, nodeId, &browseName);
    if(retval == UA_STATUSCODE_GOOD) {
        printf("Browse Name: %.*s (ns=%d)\n", 
               (int)browseName.name.length, browseName.name.data,
               browseName.namespaceIndex);
    }
    UA_QualifiedName_clear(&browseName);
    
    // 2. Read the display name
    UA_LocalizedText displayName;
    UA_LocalizedText_init(&displayName);
    retval = UA_Client_readDisplayNameAttribute(client, nodeId, &displayName);
    if(retval == UA_STATUSCODE_GOOD) {
        printf("Display Name: %.*s\n", 
               (int)displayName.text.length, displayName.text.data);
    }
    UA_LocalizedText_clear(&displayName);
    
    // 3. Read the data type attribute
    UA_NodeId dataTypeId;
    UA_NodeId_init(&dataTypeId);
    retval = UA_Client_readDataTypeAttribute(client, nodeId, &dataTypeId);
    if(retval == UA_STATUSCODE_GOOD) {
        printf("Data Type NodeId: ns=%d;i=%d\n", 
               dataTypeId.namespaceIndex, dataTypeId.identifier.numeric);
        
        // Get the name of the data type
        UA_QualifiedName dataTypeName;
        UA_QualifiedName_init(&dataTypeName);
        if(UA_Client_readBrowseNameAttribute(client, dataTypeId, &dataTypeName) == UA_STATUSCODE_GOOD) {
            printf("Data Type Name: %.*s\n", 
                   (int)dataTypeName.name.length, dataTypeName.name.data);
        }
        UA_QualifiedName_clear(&dataTypeName);
    }
    UA_NodeId_clear(&dataTypeId);
    
    // 4. Read the actual value
    UA_Variant value;
    UA_Variant_init(&value);
    retval = UA_Client_readValueAttribute(client, nodeId, &value);
    printf("\nValue Read Status: %s (0x%08X)\n", UA_StatusCode_name(retval), retval);
    
    if(retval == UA_STATUSCODE_GOOD) {
        printf("Has value data: %s\n", value.data ? "YES" : "NO");
        printf("Is scalar: %s\n", UA_Variant_isScalar(&value) ? "YES" : "NO");
        
        if(value.type) {
            printf("Runtime Type ID: ns=%d;i=%d\n", 
                   value.type->typeId.namespaceIndex,
                   value.type->typeId.identifier.numeric);
            printf("Runtime Type Name: %s\n", value.type->typeName);
            printf("Memory size: %d bytes\n", value.type->memSize);
            
            // Check if it matches standard types
            if(UA_Variant_hasScalarType(&value, &UA_TYPES[UA_TYPES_DOUBLE])) {
                printf("Type Match: DOUBLE (standard)\n");
                printf("Value: %.6f\n", *(UA_Double*)value.data);
            } else if(UA_Variant_hasScalarType(&value, &UA_TYPES[UA_TYPES_STRING])) {
                printf("Type Match: STRING (standard)\n");
                UA_String* str = (UA_String*)value.data;
                printf("Value: '%.*s' (length: %d)\n",
                       (int)str->length, str->data, (int)str->length);
            } else {
                printf("Type Match: UNKNOWN - not a standard type!\n");
            }
        } else {
            printf("Runtime Type: NULL\n");
        }
    }
    UA_Variant_clear(&value);
    
    // Also check ns=2;i=202 for comparison
    printf("\n\n=== Comparing with ns=2;i=202 (MotorWindingTemp) ===\n\n");
    
    UA_NodeId tempNode = UA_NODEID_NUMERIC(2, 202);
    
    // Read data type
    UA_NodeId tempDataTypeId;
    UA_NodeId_init(&tempDataTypeId);
    retval = UA_Client_readDataTypeAttribute(client, tempNode, &tempDataTypeId);
    if(retval == UA_STATUSCODE_GOOD) {
        printf("Data Type NodeId: ns=%d;i=%d\n", 
               tempDataTypeId.namespaceIndex, tempDataTypeId.identifier.numeric);
    }
    UA_NodeId_clear(&tempDataTypeId);
    
    // Read value
    UA_Variant tempValue;
    UA_Variant_init(&tempValue);
    retval = UA_Client_readValueAttribute(client, tempNode, &tempValue);
    if(retval == UA_STATUSCODE_GOOD && tempValue.type) {
        printf("Runtime Type Name: %s\n", tempValue.type->typeName);
        if(UA_Variant_hasScalarType(&tempValue, &UA_TYPES[UA_TYPES_DOUBLE])) {
            printf("Type Match: DOUBLE (standard)\n");
            printf("Value: %.6f\n", *(UA_Double*)tempValue.data);
        } else {
            printf("Type Match: UNKNOWN\n");
        }
    }
    UA_Variant_clear(&tempValue);
    
    UA_Client_disconnect(client);
    UA_Client_delete(client);
    
    return 0;
}
