#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <open62541/client.h>
#include <open62541/client_config_default.h>
#include <open62541/client_highlevel.h>

void browseNode(UA_Client *client, UA_NodeId nodeId, int depth) {
    if(depth > 3) return; // Limit recursion depth
    
    UA_BrowseRequest bReq;
    UA_BrowseRequest_init(&bReq);
    bReq.requestedMaxReferencesPerNode = 128;
    bReq.nodesToBrowse = UA_BrowseDescription_new();
    if(!bReq.nodesToBrowse) {
        fprintf(stderr, "Failed to allocate browse description\n");
        UA_BrowseRequest_clear(&bReq);
        return;
    }
    bReq.nodesToBrowseSize = 1;
    bReq.nodesToBrowse[0].nodeId = nodeId;
    bReq.nodesToBrowse[0].resultMask = UA_BROWSERESULTMASK_ALL;
    
    UA_BrowseResponse bResp = UA_Client_Service_browse(client, bReq);
    
    for(size_t i = 0; bResp.results && i < bResp.resultsSize; ++i) {
        for(size_t j = 0; j < bResp.results[i].referencesSize; ++j) {
            UA_ReferenceDescription *ref = &(bResp.results[i].references[j]);
            
            // Only show variables
            if(ref->nodeClass == UA_NODECLASS_VARIABLE) {
                // Indent based on depth
                for(int d = 0; d < depth; d++) printf("  ");
                
                // Print node info
                printf("Variable: %.*s", (int)ref->displayName.text.length, ref->displayName.text.data);
                
                // Print NodeId
                if(ref->nodeId.nodeId.identifierType == UA_NODEIDTYPE_NUMERIC) {
                    printf(" (ns=%d;i=%d)", ref->nodeId.nodeId.namespaceIndex, 
                           ref->nodeId.nodeId.identifier.numeric);
                }
                
                // Try to read the value and its type
                UA_Variant value;
                UA_Variant_init(&value);
                UA_StatusCode retval = UA_Client_readValueAttribute(client, ref->nodeId.nodeId, &value);
                if(retval == UA_STATUSCODE_GOOD && UA_Variant_isScalar(&value)) {
                    if(UA_Variant_hasScalarType(&value, &UA_TYPES[UA_TYPES_DOUBLE])) {
                        printf(" = %.2f (Double)", *(UA_Double*)value.data);
                    } else if(UA_Variant_hasScalarType(&value, &UA_TYPES[UA_TYPES_FLOAT])) {
                        printf(" = %.2f (Float)", *(UA_Float*)value.data);
                    } else if(UA_Variant_hasScalarType(&value, &UA_TYPES[UA_TYPES_INT32])) {
                        printf(" = %d (Int32)", *(UA_Int32*)value.data);
                    } else if(UA_Variant_hasScalarType(&value, &UA_TYPES[UA_TYPES_STRING])) {
                        UA_String* str = (UA_String*)value.data;
                        if(str->length > 0) {
                            printf(" = '%.*s' (String)", (int)str->length, str->data);
                        } else {
                            printf(" = '' (Empty String)");
                        }
                    } else {
                        printf(" (Type: %s)", value.type->typeName);
                    }
                } else {
                    printf(" (No value)");
                }
                UA_Variant_clear(&value);
                
                printf("\n");
            }
            
            // Recurse into objects
            if(ref->nodeClass == UA_NODECLASS_OBJECT && depth < 3) {
                for(int d = 0; d < depth; d++) printf("  ");
                printf("Object: %.*s\n", (int)ref->displayName.text.length, ref->displayName.text.data);
                browseNode(client, ref->nodeId.nodeId, depth + 1);
            }
        }
    }
    
    UA_BrowseRequest_clear(&bReq);
    UA_BrowseResponse_clear(&bResp);
}

int main() {
    printf("=== Browsing OPC UA Server for Variables ===\n\n");
    
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
    
    printf("Connected. Browsing namespace 2 (simulation data):\n\n");
    
    // Browse the Objects folder in namespace 2
    printf("Looking for simulation variables:\n");
    
    // Try browsing from different starting points
    UA_NodeId rootFolder = UA_NODEID_NUMERIC(0, 85); // Objects folder
    browseNode(client, rootFolder, 0);
    
    printf("\nDirect check of specific nodes:\n");
    
    // Check nodes around 187
    for(int i = 180; i <= 210; i++) {
        UA_NodeId testNode = UA_NODEID_NUMERIC(2, i);
        UA_Variant value;
        UA_Variant_init(&value);
        
        UA_StatusCode status = UA_Client_readValueAttribute(client, testNode, &value);
        if(status == UA_STATUSCODE_GOOD && UA_Variant_isScalar(&value)) {
            printf("  ns=2;i=%d: ", i);
            
            if(UA_Variant_hasScalarType(&value, &UA_TYPES[UA_TYPES_DOUBLE])) {
                printf("%.2f (Double)\n", *(UA_Double*)value.data);
            } else if(UA_Variant_hasScalarType(&value, &UA_TYPES[UA_TYPES_FLOAT])) {
                printf("%.2f (Float)\n", *(UA_Float*)value.data);
            } else if(UA_Variant_hasScalarType(&value, &UA_TYPES[UA_TYPES_STRING])) {
                UA_String* str = (UA_String*)value.data;
                if(str->length > 0) {
                    printf("'%.*s' (String)\n", (int)str->length, str->data);
                } else {
                    printf("'' (Empty String)\n");
                }
            } else if(UA_Variant_hasScalarType(&value, &UA_TYPES[UA_TYPES_INT32])) {
                printf("%d (Int32)\n", *(UA_Int32*)value.data);
            } else {
                printf("Type: %s\n", value.type->typeName);
            }
        }
        UA_Variant_clear(&value);
    }
    
    UA_Client_disconnect(client);
    UA_Client_delete(client);
    
    return 0;
}
