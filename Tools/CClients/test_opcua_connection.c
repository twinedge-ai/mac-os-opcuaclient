#include <open62541/client.h>
#include <open62541/client_config_default.h>
#include <open62541/client_highlevel.h>
#include <stdio.h>

int main() {
    UA_Client *client = UA_Client_new();
    if(!client) {
        fprintf(stderr, "Failed to allocate OPC UA client\n");
        return 1;
    }
    UA_ClientConfig_setDefault(UA_Client_getConfig(client));

    // Test connection to Eclipse Milo demo server
    const char *endpointUrl = "opc.tcp://milo.digitalpetri.com:62541/milo";
    
    printf("Connecting to %s...\n", endpointUrl);
    UA_StatusCode retval = UA_Client_connect(client, endpointUrl);
    
    if(retval == UA_STATUSCODE_GOOD) {
        printf("✅ Successfully connected to OPC UA server!\n");
        
        // Test reading a value
        UA_Variant value;
        UA_Variant_init(&value);
        
        UA_NodeId nodeId = UA_NODEID_STRING(2, "Dynamic/RandomInt32");
        retval = UA_Client_readValueAttribute(client, nodeId, &value);
        
        if(retval == UA_STATUSCODE_GOOD && UA_Variant_hasScalarType(&value, &UA_TYPES[UA_TYPES_INT32])) {
            UA_Int32 intValue = *(UA_Int32*)value.data;
            printf("✅ Read value: %d\n", intValue);
        } else {
            printf("⚠️  Could not read value, status: 0x%08x\n", retval);
        }
        
        UA_Variant_clear(&value);
    } else {
        printf("❌ Failed to connect, status: 0x%08x (%s)\n", retval, UA_StatusCode_name(retval));
    }

    UA_Client_disconnect(client);
    UA_Client_delete(client);
    return retval == UA_STATUSCODE_GOOD ? 0 : 1;
}
