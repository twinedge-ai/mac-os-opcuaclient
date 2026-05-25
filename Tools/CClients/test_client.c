#include <open62541/client_config_default.h>
#include <open62541/client_highlevel.h>
#include <open62541/plugin/log_stdout.h>
#include <stdio.h>

int main(void) {
    UA_Client *client = UA_Client_new();
    if(!client) {
        fprintf(stderr, "Failed to allocate OPC UA client\n");
        return 1;
    }
    UA_ClientConfig_setDefault(UA_Client_getConfig(client));
    
    printf("🔗 Connecting to OPC UA server at opc.tcp://localhost:10000\n");
    UA_StatusCode retval = UA_Client_connect(client, "opc.tcp://localhost:10000");
    
    if(retval != UA_STATUSCODE_GOOD) {
        printf("❌ Connection failed with status code %s\n", UA_StatusCode_name(retval));
        UA_Client_delete(client);
        return 0;
    }
    
    printf("✅ Connected successfully!\n");
    
    // Browse root folder
    printf("📁 Browsing root folder...\n");
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
    printf("Found %lu references:\n", (unsigned long)bResp.resultsSize);
    
    for(size_t i = 0; bResp.results && i < bResp.resultsSize; ++i) {
        for(size_t j = 0; j < bResp.results[i].referencesSize; ++j) {
            UA_ReferenceDescription *ref = &(bResp.results[i].references[j]);
            if(ref->nodeId.nodeId.identifierType == UA_NODEIDTYPE_STRING) {
                printf("📄 Node: %.*s\n", 
                       (int)ref->nodeId.nodeId.identifier.string.length,
                       ref->nodeId.nodeId.identifier.string.data);
            }
        }
    }
    
    UA_BrowseRequest_clear(&bReq);
    UA_BrowseResponse_clear(&bResp);
    UA_Client_delete(client);
    return 0;
}
