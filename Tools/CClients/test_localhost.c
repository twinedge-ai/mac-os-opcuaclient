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
    
    // Test connection to local server
    const char *endpointUrl = "opc.tcp://localhost:10000";
    
    printf("Connecting to %s...\n", endpointUrl);
    UA_StatusCode retval = UA_Client_connect(client, endpointUrl);
    
    if(retval == UA_STATUSCODE_GOOD) {
        printf("✅ Successfully connected to OPC UA server!\n");
        
        // Test browsing the address space
        UA_BrowseRequest bReq;
        UA_BrowseRequest_init(&bReq);
        bReq.requestedMaxReferencesPerNode = 128;
        bReq.nodesToBrowse = UA_BrowseDescription_new();
        if(!bReq.nodesToBrowse) {
            fprintf(stderr, "Failed to allocate browse description\n");
            UA_BrowseRequest_clear(&bReq);
            UA_Client_disconnect(client);
            UA_Client_delete(client);
            return 1;
        }
        bReq.nodesToBrowseSize = 1;
        bReq.nodesToBrowse[0].nodeId = UA_NODEID_NUMERIC(0, UA_NS0ID_OBJECTSFOLDER);
        bReq.nodesToBrowse[0].resultMask = UA_BROWSERESULTMASK_ALL;
        
        UA_BrowseResponse bResp = UA_Client_Service_browse(client, bReq);
        
        if(bResp.responseHeader.serviceResult == UA_STATUSCODE_GOOD) {
            printf("✅ Browse successful, results: %d\n", (int)bResp.resultsSize);
            
            for(size_t i = 0; bResp.results && i < bResp.resultsSize; ++i) {
                for(size_t j = 0; j < bResp.results[i].referencesSize; ++j) {
                    UA_ReferenceDescription *ref = &(bResp.results[i].references[j]);
                    printf("   Reference %zu: DisplayName='%.*s'\n",
                           j,
                           (int)ref->displayName.text.length,
                           ref->displayName.text.data);
                }
            }
        } else {
            printf("❌ Browse failed, status: 0x%08x\n", bResp.responseHeader.serviceResult);
        }
        
        UA_BrowseRequest_clear(&bReq);
        UA_BrowseResponse_clear(&bResp);
        
    } else {
        printf("❌ Failed to connect, status: 0x%08x (%s)\n", retval, UA_StatusCode_name(retval));
    }

    UA_Client_disconnect(client);
    UA_Client_delete(client);
    return retval == UA_STATUSCODE_GOOD ? 0 : 1;
}
