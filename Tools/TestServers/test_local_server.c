#include <open62541/client_config_default.h>
#include <open62541/client_highlevel.h>
#include <open62541/plugin/log_stdout.h>
#include <stdio.h>
#include <stdlib.h>

int main() {
    UA_Client *client = UA_Client_new();
    if(!client) {
        fprintf(stderr, "Failed to allocate OPC UA client\n");
        return EXIT_FAILURE;
    }
    UA_ClientConfig_setDefault(UA_Client_getConfig(client));

    printf("🔗 Testing connection to local OPC UA server...\n");
    
    UA_StatusCode retval = UA_Client_connect(client, "opc.tcp://localhost:4840");
    if(retval != UA_STATUSCODE_GOOD) {
        printf("❌ Connection failed: %s\n", UA_StatusCode_name(retval));
        UA_Client_delete(client);
        return EXIT_FAILURE;
    }

    printf("✅ Connected to local OPC UA server!\n");

    // Try to browse the Objects folder
    printf("📁 Browsing Objects folder (ns=0;i=85)...\n");
    
    UA_BrowseRequest bReq;
    UA_BrowseRequest_init(&bReq);
    bReq.requestedMaxReferencesPerNode = 128;
    bReq.nodesToBrowse = UA_BrowseDescription_new();
    if(!bReq.nodesToBrowse) {
        fprintf(stderr, "Failed to allocate browse description\n");
        UA_BrowseRequest_clear(&bReq);
        UA_Client_disconnect(client);
        UA_Client_delete(client);
        return EXIT_FAILURE;
    }
    bReq.nodesToBrowseSize = 1;
    bReq.nodesToBrowse[0].nodeId = UA_NODEID_NUMERIC(0, UA_NS0ID_OBJECTSFOLDER); // Objects folder
    bReq.nodesToBrowse[0].resultMask = UA_BROWSERESULTMASK_ALL;

    UA_BrowseResponse bResp = UA_Client_Service_browse(client, bReq);

    if(bResp.responseHeader.serviceResult == UA_STATUSCODE_GOOD) {
        printf("📋 Browse successful! Found %lu references:\n", (unsigned long)bResp.resultsSize);
        
        for(size_t i = 0; bResp.results && i < bResp.resultsSize; i++) {
            UA_BrowseResult *result = &bResp.results[i];
            
            printf("  Result %lu: %lu references\n", (unsigned long)i, (unsigned long)result->referencesSize);
            
            for(size_t j = 0; j < result->referencesSize; j++) {
                UA_ReferenceDescription *ref = &result->references[j];
                
                if(ref->displayName.text.length > 0) {
                    printf("    - %.*s", (int)ref->displayName.text.length, ref->displayName.text.data);
                    
                    // Print NodeId if available
                    if(ref->nodeId.nodeId.identifierType == UA_NODEIDTYPE_NUMERIC) {
                        printf(" (ns=%d;i=%d)", ref->nodeId.nodeId.namespaceIndex, ref->nodeId.nodeId.identifier.numeric);
                    } else if(ref->nodeId.nodeId.identifierType == UA_NODEIDTYPE_STRING) {
                        printf(" (ns=%d;s=%.*s)", ref->nodeId.nodeId.namespaceIndex,
                               (int)ref->nodeId.nodeId.identifier.string.length,
                               ref->nodeId.nodeId.identifier.string.data);
                    }
                    printf("\n");
                } else {
                    printf("    - (unnamed node)\n");
                }
            }
        }
    } else {
        printf("❌ Browse failed: %s\n", UA_StatusCode_name(bResp.responseHeader.serviceResult));
    }

    UA_BrowseResponse_clear(&bResp);
    UA_BrowseRequest_clear(&bReq);

    printf("📤 Disconnecting...\n");
    UA_Client_disconnect(client);
    UA_Client_delete(client);
    
    printf("🧪 Test completed\n");
    return EXIT_SUCCESS;
}
