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
    
    // Test connection to local server on port 10000
    const char *endpointUrl = "opc.tcp://localhost:10000";
    
    printf("Connecting to %s...\n", endpointUrl);
    UA_StatusCode retval = UA_Client_connect(client, endpointUrl);
    
    if(retval == UA_STATUSCODE_GOOD) {
        printf("✅ Successfully connected to OPC UA server!\n");
        
        // Test browsing the address space - start with Objects (i=85)
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
        bReq.nodesToBrowse[0].nodeId = UA_NODEID_NUMERIC(0, UA_NS0ID_OBJECTSFOLDER); // i=85
        bReq.nodesToBrowse[0].resultMask = UA_BROWSERESULTMASK_ALL;
        bReq.nodesToBrowse[0].browseDirection = UA_BROWSEDIRECTION_FORWARD;
        bReq.nodesToBrowse[0].referenceTypeId = UA_NODEID_NUMERIC(0, UA_NS0ID_HIERARCHICALREFERENCES); // i=33
        bReq.nodesToBrowse[0].includeSubtypes = true;
        
        UA_BrowseResponse bResp = UA_Client_Service_browse(client, bReq);
        
        if(bResp.responseHeader.serviceResult == UA_STATUSCODE_GOOD) {
            printf("✅ Browse successful!\n");
            printf("Results count: %d\n", (int)bResp.resultsSize);
            
            for(size_t i = 0; bResp.results && i < bResp.resultsSize; ++i) {
                printf("Browse result %d:\n", (int)i);
                printf("  Status: 0x%08x\n", bResp.results[i].statusCode);
                printf("  References count: %d\n", (int)bResp.results[i].referencesSize);
                
                for(size_t j = 0; j < bResp.results[i].referencesSize; ++j) {
                    UA_ReferenceDescription *ref = &(bResp.results[i].references[j]);
                    printf("   Reference %zu:\n", j);
                    printf("     DisplayName: '%.*s'\n",
                           (int)ref->displayName.text.length,
                           ref->displayName.text.data);
                    printf("     NodeClass: %d\n", ref->nodeClass);
                    
                    // Print NodeId
                    if(ref->nodeId.nodeId.identifierType == UA_NODEIDTYPE_NUMERIC) {
                        printf("     NodeId: ns=%d;i=%d\n",
                               ref->nodeId.nodeId.namespaceIndex,
                               ref->nodeId.nodeId.identifier.numeric);
                    }
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
