//
//  OpcUaWrapper.c
//  OpcUaClient
//

#include "OpcUaWrapper.h"
#include <open62541/client.h>
#include <open62541/client_config_default.h>
#include <open62541/client_highlevel.h>
#include <open62541/client_subscriptions.h>
#include <open62541/types.h>
#include <open62541/types_generated.h>
#include <open62541/plugin/securitypolicy.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

struct MonitoredItemContext {
    char* nodeId;
    char* lastValue;
    double lastTimestamp;
    bool hasChanged;
    uint32_t monitoredItemId;
};
typedef struct MonitoredItemContext MonitoredItemContext;

static bool parse_uint32_component(const char* start, const char* end, uint32_t* value) {
    if (!start || !end || !value || start >= end) {
        return false;
    }

    errno = 0;
    char* parsed_end = NULL;
    unsigned long parsed = strtoul(start, &parsed_end, 10);
    if (errno == ERANGE || parsed_end != end || parsed > UINT32_MAX) {
        return false;
    }

    *value = (uint32_t)parsed;
    return true;
}

struct OpcUaClient_t {
    UA_Client* client;
    bool connected;
    MonitoredItemContext** monitoredItems;
    int monitoredItemCount;
    int monitoredItemCapacity;
};

typedef struct {
    char* node_id;
    char* name;
    char* display_name;
    char* class_name;
} OpcUaNode;

struct OpcUaNodeList_t {
    OpcUaNode* nodes;
    int count;
    int capacity;
};

struct OpcUaEndpointList_t {
    char** endpoints;
    int count;
};

void opcua_node_list_destroy(OpcUaNodeList_t* list);

enum {
    OPCUA_BROWSE_REFERENCES_PER_NODE = 128,
    OPCUA_BROWSE_MAX_REFERENCES = 2048,
    OPCUA_BROWSE_MAX_STRING_BYTES = 8192
};

static OpcUaNodeList_t* opcua_node_list_create(void) {
    OpcUaNodeList_t* nodeList = malloc(sizeof(OpcUaNodeList_t));
    if (!nodeList) {
        return NULL;
    }

    nodeList->nodes = NULL;
    nodeList->count = 0;
    nodeList->capacity = 0;
    return nodeList;
}

static bool opcua_node_list_reserve(OpcUaNodeList_t* list, int needed) {
    if (!list || needed < 0 || needed > OPCUA_BROWSE_MAX_REFERENCES) {
        return false;
    }

    if (list->capacity >= needed) {
        return true;
    }

    int newCapacity = list->capacity > 0 ? list->capacity : 32;
    while (newCapacity < needed && newCapacity < OPCUA_BROWSE_MAX_REFERENCES) {
        if (newCapacity > OPCUA_BROWSE_MAX_REFERENCES / 2) {
            newCapacity = OPCUA_BROWSE_MAX_REFERENCES;
        } else {
            newCapacity *= 2;
        }
    }

    if (newCapacity < needed) {
        return false;
    }

    OpcUaNode* resized = realloc(list->nodes, sizeof(OpcUaNode) * (size_t)newCapacity);
    if (!resized) {
        return false;
    }

    list->nodes = resized;
    list->capacity = newCapacity;
    return true;
}

static char* copy_ua_string_limited(const UA_String* value) {
    if (!value || value->length == 0 || !value->data) {
        return NULL;
    }

    if (value->length > OPCUA_BROWSE_MAX_STRING_BYTES) {
        return NULL;
    }

    char* copy = malloc(value->length + 1);
    if (!copy) {
        return NULL;
    }

    memcpy(copy, value->data, value->length);
    copy[value->length] = '\0';
    return copy;
}

static char* node_id_to_string_limited(const UA_NodeId* nodeId, UA_UInt16 namespaceIndex) {
    if (!nodeId) {
        return NULL;
    }

    if (nodeId->identifierType == UA_NODEIDTYPE_STRING) {
        size_t id_len = nodeId->identifier.string.length;
        if (id_len > OPCUA_BROWSE_MAX_STRING_BYTES || !nodeId->identifier.string.data) {
            return NULL;
        }

        size_t bufferSize = id_len + 32;
        char* node_id = malloc(bufferSize);
        if (!node_id) {
            return NULL;
        }

        snprintf(node_id, bufferSize, "ns=%u;s=%.*s",
                 namespaceIndex,
                 (int)id_len,
                 nodeId->identifier.string.data);
        return node_id;
    }

    if (nodeId->identifierType == UA_NODEIDTYPE_NUMERIC) {
        char* node_id = malloc(50);
        if (!node_id) {
            return NULL;
        }

        snprintf(node_id, 50, "ns=%u;i=%u",
                 namespaceIndex,
                 nodeId->identifier.numeric);
        return node_id;
    }

    return NULL;
}

static char* node_class_to_string(UA_NodeClass nodeClass) {
    switch (nodeClass) {
        case UA_NODECLASS_OBJECT:
            return strdup("Object");
        case UA_NODECLASS_VARIABLE:
            return strdup("Variable");
        case UA_NODECLASS_METHOD:
            return strdup("Method");
        case UA_NODECLASS_OBJECTTYPE:
            return strdup("ObjectType");
        case UA_NODECLASS_VARIABLETYPE:
            return strdup("VariableType");
        case UA_NODECLASS_REFERENCETYPE:
            return strdup("ReferenceType");
        case UA_NODECLASS_DATATYPE:
            return strdup("DataType");
        case UA_NODECLASS_VIEW:
            return strdup("View");
        default:
            return strdup("Unknown");
    }
}

static bool append_reference_to_node_list(OpcUaNodeList_t* nodeList, const UA_ReferenceDescription* ref) {
    if (!nodeList || !ref || nodeList->count >= OPCUA_BROWSE_MAX_REFERENCES) {
        return false;
    }

    if (!opcua_node_list_reserve(nodeList, nodeList->count + 1)) {
        return false;
    }

    OpcUaNode* node = &nodeList->nodes[nodeList->count];
    node->node_id = node_id_to_string_limited(&ref->nodeId.nodeId, ref->nodeId.nodeId.namespaceIndex);
    node->name = copy_ua_string_limited(&ref->browseName.name);
    node->display_name = copy_ua_string_limited(&ref->displayName.text);
    node->class_name = node_class_to_string(ref->nodeClass);

    nodeList->count++;
    return true;
}

OpcUaClient_t* opcua_client_create(void) {
    OpcUaClient_t* wrapper = malloc(sizeof(OpcUaClient_t));
    if (!wrapper) return NULL;
    
    wrapper->client = UA_Client_new();
    if (!wrapper->client) {
        free(wrapper);
        return NULL;
    }
    
    UA_ClientConfig_setDefault(UA_Client_getConfig(wrapper->client));
    wrapper->connected = false;
    
    // Initialize monitoring storage
    wrapper->monitoredItemCapacity = 100;
    wrapper->monitoredItemCount = 0;
    wrapper->monitoredItems = calloc(wrapper->monitoredItemCapacity, sizeof(MonitoredItemContext*));
    
    return wrapper;
}

void opcua_client_destroy(OpcUaClient_t* client) {
    if (!client) return;
    
    if (client->connected) {
        opcua_client_disconnect(client);
    }
    
    if (client->client) {
        UA_Client_delete(client->client);
    }
    
    // Free monitored items
    if (client->monitoredItems) {
        for (int i = 0; i < client->monitoredItemCount; i++) {
            if (client->monitoredItems[i]) {
                free(client->monitoredItems[i]->nodeId);
                free(client->monitoredItems[i]->lastValue);
                free(client->monitoredItems[i]);
            }
        }
        free(client->monitoredItems);
    }
    
    free(client);
}

bool opcua_client_connect(OpcUaClient_t* client, const char* endpoint) {
    if (!client || !client->client || !endpoint) return false;
    
    UA_StatusCode result = UA_Client_connect(client->client, endpoint);
    client->connected = (result == UA_STATUSCODE_GOOD);
    
    return client->connected;
}

bool opcua_client_connect_username(OpcUaClient_t* client, const char* endpoint, const char* username, const char* password) {
    if (!client || !client->client || !endpoint || !username || !password) return false;

    UA_StatusCode result = UA_Client_connectUsername(client->client, endpoint, username, password);
    client->connected = (result == UA_STATUSCODE_GOOD);

    return client->connected;
}

void opcua_client_disconnect(OpcUaClient_t* client) {
    if (!client || !client->client || !client->connected) return;
    
    UA_Client_disconnect(client->client);
    client->connected = false;
}

static UA_String security_policy_uri_from_name(const char* name) {
    if (!name) return UA_SECURITY_POLICY_NONE_URI;

    if (strcmp(name, "None") == 0) {
        return UA_SECURITY_POLICY_NONE_URI;
    }
    if (strcmp(name, "Basic128Rsa15") == 0) {
        return UA_STRING("http://opcfoundation.org/UA/SecurityPolicy#Basic128Rsa15");
    }
    if (strcmp(name, "Basic256") == 0) {
        return UA_STRING("http://opcfoundation.org/UA/SecurityPolicy#Basic256");
    }
    if (strcmp(name, "Basic256Sha256") == 0) {
        return UA_STRING("http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256");
    }
    if (strcmp(name, "Aes128_Sha256_RsaOaep") == 0) {
        return UA_STRING("http://opcfoundation.org/UA/SecurityPolicy#Aes128_Sha256_RsaOaep");
    }
    if (strcmp(name, "Aes256_Sha256_RsaPss") == 0) {
        return UA_STRING("http://opcfoundation.org/UA/SecurityPolicy#Aes256_Sha256_RsaPss");
    }

    return UA_SECURITY_POLICY_NONE_URI;
}

static UA_StatusCode load_file_to_bytestring(const char* path, UA_ByteString* out) {
    if (!path || !out) return UA_STATUSCODE_BADINVALIDARGUMENT;

    FILE* file = fopen(path, "rb");
    if (!file) return UA_STATUSCODE_BADNOTFOUND;

    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return UA_STATUSCODE_BADUNEXPECTEDERROR;
    }

    long size = ftell(file);
    if (size <= 0) {
        fclose(file);
        return UA_STATUSCODE_BADUNEXPECTEDERROR;
    }

    rewind(file);

    UA_StatusCode result = UA_ByteString_allocBuffer(out, (size_t)size);
    if (result != UA_STATUSCODE_GOOD) {
        fclose(file);
        return result;
    }

    size_t read = fread(out->data, 1, (size_t)size, file);
    fclose(file);

    if (read != (size_t)size) {
        UA_ByteString_clear(out);
        return UA_STATUSCODE_BADUNEXPECTEDERROR;
    }

    out->length = (size_t)size;
    return UA_STATUSCODE_GOOD;
}

bool opcua_client_configure_security(
    OpcUaClient_t* client,
    const char* security_policy,
    int security_mode,
    const char* client_cert_path,
    const char* client_key_path,
    const char* server_cert_path
) {
    if (!client || !client->client) {
        return false;
    }

    UA_ClientConfig* config = UA_Client_getConfig(client->client);
    if (!config) {
        return false;
    }

    UA_String policyUri = security_policy_uri_from_name(security_policy);
    bool policyNone = UA_String_equal(&policyUri, &UA_SECURITY_POLICY_NONE_URI);
    if (policyNone && security_policy && strcmp(security_policy, "None") != 0) {
        return false;
    }

    if (policyNone) {
        if (security_mode != UA_MESSAGESECURITYMODE_INVALID &&
            security_mode != UA_MESSAGESECURITYMODE_NONE) {
            return false;
        }
        UA_ClientConfig_setDefault(config);
        return true;
    }

    if (security_mode != UA_MESSAGESECURITYMODE_SIGN &&
        security_mode != UA_MESSAGESECURITYMODE_SIGNANDENCRYPT) {
        return false;
    }

    if (!client_cert_path || !client_key_path) {
        return false;
    }

    // Defense in depth: an empty or missing server certificate path with
    // security enabled would result in trustListSize=0, which open62541
    // interprets as "trust any server" — MITM-exploitable. The Swift caller
    // also rejects this, but enforce it here so any future caller of this C
    // ABI gets the same protection.
    if (!server_cert_path || strlen(server_cert_path) == 0) {
        return false;
    }

    UA_ByteString clientCert = UA_BYTESTRING_NULL;
    UA_ByteString privateKey = UA_BYTESTRING_NULL;
    UA_ByteString trustList[1];

    UA_StatusCode result = load_file_to_bytestring(client_cert_path, &clientCert);
    if (result != UA_STATUSCODE_GOOD) {
        return false;
    }

    result = load_file_to_bytestring(client_key_path, &privateKey);
    if (result != UA_STATUSCODE_GOOD) {
        UA_ByteString_clear(&clientCert);
        return false;
    }

    result = load_file_to_bytestring(server_cert_path, &trustList[0]);
    if (result != UA_STATUSCODE_GOOD) {
        UA_ByteString_clear(&clientCert);
        UA_ByteString_clear(&privateKey);
        return false;
    }

#ifdef UA_ENABLE_ENCRYPTION
    UA_ClientConfig_setDefaultEncryption(config, clientCert, privateKey, trustList, 1, NULL, 0);

    UA_String_clear(&config->securityPolicyUri);
    UA_String_copy(&policyUri, &config->securityPolicyUri);
    config->securityMode = (UA_MessageSecurityMode)security_mode;

    UA_ByteString_clear(&clientCert);
    UA_ByteString_clear(&privateKey);
    UA_ByteString_clear(&trustList[0]);
    return true;
#else
    UA_ByteString_clear(&clientCert);
    UA_ByteString_clear(&privateKey);
    UA_ByteString_clear(&trustList[0]);
    return false;
#endif
}

bool opcua_client_configure_certificate_auth(
    OpcUaClient_t* client,
    const char* client_cert_path,
    const char* client_key_path
) {
    if (!client || !client->client || !client_cert_path || !client_key_path) {
        return false;
    }

    UA_ClientConfig* config = UA_Client_getConfig(client->client);
    if (!config) {
        return false;
    }

#if defined(UA_ENABLE_ENCRYPTION_OPENSSL) || defined(UA_ENABLE_ENCRYPTION_MBEDTLS)
    UA_ByteString authCert = UA_BYTESTRING_NULL;
    UA_ByteString authKey = UA_BYTESTRING_NULL;

    UA_StatusCode result = load_file_to_bytestring(client_cert_path, &authCert);
    if (result != UA_STATUSCODE_GOOD) {
        return false;
    }

    result = load_file_to_bytestring(client_key_path, &authKey);
    if (result != UA_STATUSCODE_GOOD) {
        UA_ByteString_clear(&authCert);
        return false;
    }

    result = UA_ClientConfig_setAuthenticationCert(config, authCert, authKey);
    UA_ByteString_clear(&authCert);
    UA_ByteString_clear(&authKey);
    return result == UA_STATUSCODE_GOOD;
#else
    (void)config;
    return false;
#endif
}

static bool copy_browse_result_references(OpcUaNodeList_t* nodeList, UA_BrowseResult* result) {
    if (!nodeList || !result) {
        return false;
    }

    for (size_t i = 0; i < result->referencesSize; i++) {
        if (nodeList->count >= OPCUA_BROWSE_MAX_REFERENCES) {
            return false;
        }

        if (!append_reference_to_node_list(nodeList, &result->references[i])) {
            return false;
        }
    }

    return true;
}

static void release_browse_continuation_point(UA_Client* client, UA_ByteString* continuationPoint) {
    if (!client || !continuationPoint || continuationPoint->length == 0 || !continuationPoint->data) {
        return;
    }

    UA_BrowseNextRequest releaseReq;
    UA_BrowseNextRequest_init(&releaseReq);
    releaseReq.releaseContinuationPoints = true;
    releaseReq.continuationPointsSize = 1;
    releaseReq.continuationPoints = continuationPoint;

    UA_BrowseNextResponse releaseResp = UA_Client_Service_browseNext(client, releaseReq);
    UA_BrowseNextResponse_clear(&releaseResp);
}

static OpcUaNodeList_t* browse_node_limited(OpcUaClient_t* client, UA_NodeId targetNode) {
    if (!client || !client->client || !client->connected) {
        return NULL;
    }

    OpcUaNodeList_t* nodeList = opcua_node_list_create();
    if (!nodeList) {
        return NULL;
    }

    UA_BrowseRequest bReq;
    UA_BrowseRequest_init(&bReq);
    bReq.requestedMaxReferencesPerNode = OPCUA_BROWSE_REFERENCES_PER_NODE;
    bReq.nodesToBrowse = UA_BrowseDescription_new();
    if (!bReq.nodesToBrowse) {
        UA_BrowseRequest_clear(&bReq);
        opcua_node_list_destroy(nodeList);
        return NULL;
    }

    bReq.nodesToBrowseSize = 1;
    if (UA_NodeId_copy(&targetNode, &bReq.nodesToBrowse[0].nodeId) != UA_STATUSCODE_GOOD) {
        UA_BrowseRequest_clear(&bReq);
        opcua_node_list_destroy(nodeList);
        return NULL;
    }
    bReq.nodesToBrowse[0].resultMask = UA_BROWSERESULTMASK_ALL;
    bReq.nodesToBrowse[0].browseDirection = UA_BROWSEDIRECTION_FORWARD;
    bReq.nodesToBrowse[0].referenceTypeId = UA_NODEID_NUMERIC(0, UA_NS0ID_HIERARCHICALREFERENCES);
    bReq.nodesToBrowse[0].includeSubtypes = true;

    UA_ByteString continuationPoint = UA_BYTESTRING_NULL;
    bool shouldReleaseContinuation = false;

    UA_BrowseResponse bResp = UA_Client_Service_browse(client->client, bReq);
    UA_BrowseRequest_clear(&bReq);

    if (bResp.results && bResp.resultsSize > 0) {
        UA_BrowseResult* result = &bResp.results[0];
        copy_browse_result_references(nodeList, result);
        if (result->continuationPoint.length > 0 && result->continuationPoint.data) {
            if (UA_ByteString_copy(&result->continuationPoint, &continuationPoint) == UA_STATUSCODE_GOOD) {
                shouldReleaseContinuation = true;
            }
        }
    }

    UA_BrowseResponse_clear(&bResp);

    while (shouldReleaseContinuation && nodeList->count < OPCUA_BROWSE_MAX_REFERENCES) {
        UA_BrowseNextRequest nextReq;
        UA_BrowseNextRequest_init(&nextReq);
        nextReq.releaseContinuationPoints = false;
        nextReq.continuationPointsSize = 1;
        nextReq.continuationPoints = &continuationPoint;

        UA_BrowseNextResponse nextResp = UA_Client_Service_browseNext(client->client, nextReq);
        UA_ByteString_clear(&continuationPoint);
        continuationPoint = UA_BYTESTRING_NULL;
        shouldReleaseContinuation = false;

        if (!nextResp.results || nextResp.resultsSize == 0) {
            UA_BrowseNextResponse_clear(&nextResp);
            break;
        }

        UA_BrowseResult* result = &nextResp.results[0];
        if (!copy_browse_result_references(nodeList, result)) {
            if (result->continuationPoint.length > 0 && result->continuationPoint.data &&
                UA_ByteString_copy(&result->continuationPoint, &continuationPoint) == UA_STATUSCODE_GOOD) {
                shouldReleaseContinuation = true;
            }
            UA_BrowseNextResponse_clear(&nextResp);
            break;
        }

        if (result->continuationPoint.length > 0 && result->continuationPoint.data) {
            if (UA_ByteString_copy(&result->continuationPoint, &continuationPoint) == UA_STATUSCODE_GOOD) {
                shouldReleaseContinuation = true;
            }
        }

        UA_BrowseNextResponse_clear(&nextResp);
    }

    if (shouldReleaseContinuation) {
        release_browse_continuation_point(client->client, &continuationPoint);
        UA_ByteString_clear(&continuationPoint);
    }

    return nodeList;
}

OpcUaNodeList_t* opcua_browse_root(OpcUaClient_t* client) {
    UA_NodeId rootNode = UA_NODEID_NUMERIC(0, UA_NS0ID_OBJECTSFOLDER);
    return browse_node_limited(client, rootNode);
}

// Helper function to robustly parse node ID string into UA_NodeId
static UA_NodeId parse_node_id_robust(const char* node_id_str) {
    UA_NodeId nodeId;
    UA_NodeId_init(&nodeId);
    // UA_NodeId_parse is the comprehensive built-in parser in open62541
    UA_StatusCode parseRes = UA_NodeId_parse(&nodeId, UA_STRING((char*)node_id_str));
    if (parseRes == UA_STATUSCODE_GOOD) {
        return nodeId;
    }
    UA_NodeId_clear(&nodeId);
    
    // Fallback for very simple manual formats if UA_NodeId_parse fails
    // Format: ns=X;i=Y or ns=X;s=STRING
    if (strncmp(node_id_str, "ns=", 3) == 0) {
        const char* ptr = node_id_str + 3;
        const char* semi = strchr(ptr, ';');
        uint32_t ns = 0;
        if (semi && parse_uint32_component(ptr, semi, &ns) && ns <= UINT16_MAX) {
            semi++;
            if (*semi == 'i' && *(semi + 1) == '=') {
                const char* identifier_start = semi + 2;
                const char* identifier_end = identifier_start + strlen(identifier_start);
                uint32_t identifier = 0;
                if (parse_uint32_component(identifier_start, identifier_end, &identifier)) {
                    return UA_NODEID_NUMERIC((UA_UInt16)ns, identifier);
                }
            } else if (*semi == 's' && *(semi + 1) == '=') {
                return UA_NODEID_STRING_ALLOC((UA_UInt16)ns, semi + 2);
            }
        }
    }
    
    return UA_NODEID_NULL;
}

OpcUaNodeList_t* opcua_browse_node(OpcUaClient_t* client, const char* node_id) {
    if (!client || !client->client || !client->connected || !node_id) {
        return NULL;
    }

    UA_NodeId targetNode = parse_node_id_robust(node_id);
    if (UA_NodeId_isNull(&targetNode)) {
        return NULL;
    }

    OpcUaNodeList_t* nodeList = browse_node_limited(client, targetNode);
    UA_NodeId_clear(&targetNode);
    return nodeList;
}

int opcua_read_value_double(OpcUaClient_t* client, const char* node_id, double* value) {
    if (!client || !client->client || !client->connected || !node_id || !value) {
        return 0;
    }
    
    UA_NodeId nodeId = parse_node_id_robust(node_id);
    if (UA_NodeId_isNull(&nodeId)) {
        return 0;
    }
    
    UA_Variant val;
    UA_Variant_init(&val);
    
    UA_StatusCode result = UA_Client_readValueAttribute(client->client, nodeId, &val);
    
    int success = 0;
    if (result == UA_STATUSCODE_GOOD) {
        if (UA_Variant_hasScalarType(&val, &UA_TYPES[UA_TYPES_DOUBLE])) {
            *value = *(UA_Double*)val.data;
            success = 1;
        } else if (UA_Variant_hasScalarType(&val, &UA_TYPES[UA_TYPES_FLOAT])) {
            *value = (double)(*(UA_Float*)val.data);
            success = 1;
        }
    }
    
    UA_Variant_clear(&val);
    UA_NodeId_clear(&nodeId);
    return success;
}

// Node list functions
int opcua_node_list_count(OpcUaNodeList_t* list) {
    return list ? list->count : 0;
}

const char* opcua_node_get_id(OpcUaNodeList_t* list, int index) {
    if (!list || !list->nodes || index < 0 || index >= list->count) return NULL;
    return list->nodes[index].node_id;
}

const char* opcua_node_get_name(OpcUaNodeList_t* list, int index) {
    if (!list || !list->nodes || index < 0 || index >= list->count) return NULL;
    return list->nodes[index].name;
}

const char* opcua_node_get_display_name(OpcUaNodeList_t* list, int index) {
    if (!list || !list->nodes || index < 0 || index >= list->count) return NULL;
    return list->nodes[index].display_name;
}

const char* opcua_node_get_class(OpcUaNodeList_t* list, int index) {
    if (!list || !list->nodes || index < 0 || index >= list->count) return NULL;
    return list->nodes[index].class_name;
}

void opcua_node_list_destroy(OpcUaNodeList_t* list) {
    if (!list) return;
    
    if (list->nodes) {
        for (int i = 0; i < list->count; i++) {
            free(list->nodes[i].node_id);
            free(list->nodes[i].name);
            free(list->nodes[i].display_name);
            free(list->nodes[i].class_name);
        }
        free(list->nodes);
    }
    
    free(list);
}

// Endpoint discovery list functions
OpcUaEndpointList_t* opcua_get_endpoints(const char* endpoint) {
    if (!endpoint) {
        return NULL;
    }

    UA_Client* client = UA_Client_new();
    if (!client) {
        return NULL;
    }

    UA_ClientConfig_setDefault(UA_Client_getConfig(client));

    size_t endpointCount = 0;
    UA_EndpointDescription* endpointArray = NULL;
    UA_StatusCode status = UA_Client_getEndpoints(client, endpoint, &endpointCount, &endpointArray);
    if (status != UA_STATUSCODE_GOOD || endpointCount == 0 || !endpointArray) {
        UA_Client_delete(client);
        return NULL;
    }

    OpcUaEndpointList_t* list = malloc(sizeof(OpcUaEndpointList_t));
    if (!list) {
        UA_Array_delete(endpointArray, endpointCount, &UA_TYPES[UA_TYPES_ENDPOINTDESCRIPTION]);
        UA_Client_delete(client);
        return NULL;
    }

    list->count = (int)endpointCount;
    list->endpoints = calloc(endpointCount, sizeof(char*));
    if (!list->endpoints) {
        free(list);
        UA_Array_delete(endpointArray, endpointCount, &UA_TYPES[UA_TYPES_ENDPOINTDESCRIPTION]);
        UA_Client_delete(client);
        return NULL;
    }

    for (size_t i = 0; i < endpointCount; i++) {
        UA_EndpointDescription* desc = &endpointArray[i];
        if (desc->endpointUrl.length == 0 || !desc->endpointUrl.data) {
            list->endpoints[i] = NULL;
            continue;
        }

        size_t length = desc->endpointUrl.length;
        list->endpoints[i] = malloc(length + 1);
        if (!list->endpoints[i]) {
            continue;
        }

        memcpy(list->endpoints[i], desc->endpointUrl.data, length);
        list->endpoints[i][length] = '\0';
    }

    UA_Array_delete(endpointArray, endpointCount, &UA_TYPES[UA_TYPES_ENDPOINTDESCRIPTION]);
    UA_Client_delete(client);

    return list;
}

int opcua_endpoint_list_count(OpcUaEndpointList_t* list) {
    return list ? list->count : 0;
}

const char* opcua_endpoint_get(OpcUaEndpointList_t* list, int index) {
    if (!list || !list->endpoints || index < 0 || index >= list->count) {
        return NULL;
    }
    return list->endpoints[index];
}

void opcua_endpoint_list_destroy(OpcUaEndpointList_t* list) {
    if (!list) {
        return;
    }

    if (list->endpoints) {
        for (int i = 0; i < list->count; i++) {
            free(list->endpoints[i]);
        }
        free(list->endpoints);
    }

    free(list);
}

// Generic value reading function that handles all OPC UA data types
char* opcua_read_value_string(OpcUaClient_t* client, const char* node_id) {
    if (!client || !client->client || !client->connected || !node_id) {
        return NULL;
    }
    
    // Parse the node ID properly
    UA_NodeId nodeId = parse_node_id_robust(node_id);
    if (UA_NodeId_isNull(&nodeId)) {
        return NULL;
    }
    
    UA_Variant val;
    UA_Variant_init(&val);
    
    UA_StatusCode result = UA_Client_readValueAttribute(client->client, nodeId, &val);
    
    char* valueString = NULL;
    if (result != UA_STATUSCODE_GOOD) {
        // read failed; caller treats NULL return as failure
    } else if (val.data == NULL) {
        // Return NULL instead of [NULL] to indicate no value available yet
        valueString = NULL;
    } else if (!UA_Variant_isScalar(&val)) {
        valueString = strdup("[Array]");
    } else {
        const UA_DataType* type = val.type;
        // Handle all common scalar data types - check both pointer and type ID for robustness
        // Type ID 11 is Double, 10 is Float, 12 is String, etc.
        uint16_t typeId = (type && type->typeId.identifierType == UA_NODEIDTYPE_NUMERIC) ? 
                          type->typeId.identifier.numeric : 0;
        
        if (type == &UA_TYPES[UA_TYPES_DOUBLE] || typeId == 11) {
            valueString = malloc(32);
            if (valueString) snprintf(valueString, 32, "%.6f", *(UA_Double*)val.data);
        } else if (type == &UA_TYPES[UA_TYPES_FLOAT] || typeId == 10) {
            valueString = malloc(32);
            if (valueString) snprintf(valueString, 32, "%.6f", *(UA_Float*)val.data);
        } else if (type == &UA_TYPES[UA_TYPES_INT32] || typeId == 6) {
            valueString = malloc(16);
            if (valueString) snprintf(valueString, 16, "%d", *(UA_Int32*)val.data);
        } else if (type == &UA_TYPES[UA_TYPES_UINT32] || typeId == 7) {
            valueString = malloc(16);
            if (valueString) snprintf(valueString, 16, "%u", *(UA_UInt32*)val.data);
        } else if (type == &UA_TYPES[UA_TYPES_INT16] || typeId == 4) {
            valueString = malloc(16);
            if (valueString) snprintf(valueString, 16, "%d", *(UA_Int16*)val.data);
        } else if (type == &UA_TYPES[UA_TYPES_UINT16] || typeId == 5) {
            valueString = malloc(16);
            if (valueString) snprintf(valueString, 16, "%u", *(UA_UInt16*)val.data);
        } else if (type == &UA_TYPES[UA_TYPES_BYTE] || typeId == 3) {
            valueString = malloc(16);
            if (valueString) snprintf(valueString, 16, "%u", *(UA_Byte*)val.data);
        } else if (type == &UA_TYPES[UA_TYPES_SBYTE] || typeId == 2) {
            valueString = malloc(16);
            if (valueString) snprintf(valueString, 16, "%d", *(UA_SByte*)val.data);
        } else if (type == &UA_TYPES[UA_TYPES_INT64] || typeId == 8) {
            valueString = malloc(32);
            if (valueString) snprintf(valueString, 32, "%lld", (long long)*(UA_Int64*)val.data);
        } else if (type == &UA_TYPES[UA_TYPES_UINT64] || typeId == 9) {
            valueString = malloc(32);
            if (valueString) snprintf(valueString, 32, "%llu", (unsigned long long)*(UA_UInt64*)val.data);
        } else if (type == &UA_TYPES[UA_TYPES_BOOLEAN] || typeId == 1) {
            valueString = strdup(*(UA_Boolean*)val.data ? "true" : "false");
        } else if (type == &UA_TYPES[UA_TYPES_STRING] || typeId == 12) {
            UA_String* str = (UA_String*)val.data;
            if (str->length > 0 && str->data) {
                valueString = malloc(str->length + 1);
                if (valueString) {
                    memcpy(valueString, str->data, str->length);
                    valueString[str->length] = '\0';
                }
            } else {
                valueString = strdup("");
            }
        } else if (type == &UA_TYPES[UA_TYPES_LOCALIZEDTEXT]) {
            UA_LocalizedText* lt = (UA_LocalizedText*)val.data;
            if (lt->text.length > 0 && lt->text.data) {
                valueString = malloc(lt->text.length + 1);
                if (valueString) {
                    memcpy(valueString, lt->text.data, lt->text.length);
                    valueString[lt->text.length] = '\0';
                }
            } else {
                valueString = strdup("");
            }
        } else if (type == &UA_TYPES[UA_TYPES_QUALIFIEDNAME]) {
            UA_QualifiedName* qn = (UA_QualifiedName*)val.data;
            if (qn->name.length > 0 && qn->name.data) {
                valueString = malloc(qn->name.length + 1);
                if (valueString) {
                    memcpy(valueString, qn->name.data, qn->name.length);
                    valueString[qn->name.length] = '\0';
                }
            } else {
                valueString = strdup("");
            }
        } else if (type == &UA_TYPES[UA_TYPES_ENUMERATION]) {
            valueString = malloc(16);
            if (valueString) snprintf(valueString, 16, "%d", *(UA_Int32*)val.data);
        } else if (type == &UA_TYPES[UA_TYPES_DATETIME]) {
            valueString = malloc(32);
            if (valueString) snprintf(valueString, 32, "%lld", (long long)*(UA_DateTime*)val.data);
        } else if (type == &UA_TYPES[UA_TYPES_BYTESTRING]) {
            valueString = strdup("[ByteString]");
        } else {
            valueString = NULL;
        }
    }
    
    UA_Variant_clear(&val);
    UA_NodeId_clear(&nodeId);
    return valueString;
}

void opcua_free_string(char* str) {
    if (str) {
        free(str);
    }
}

// Read the data type attribute of a node
char* opcua_read_datatype(OpcUaClient_t* client, const char* node_id) {
    if (!client || !client->client || !client->connected || !node_id) {
        return NULL;
    }
    
    // Parse the node ID
    UA_NodeId nodeId = parse_node_id_robust(node_id);
    if (UA_NodeId_isNull(&nodeId)) {
        return NULL;
    }
    
    // Read the DataType attribute
    UA_NodeId dataTypeId;
    UA_NodeId_init(&dataTypeId);
    UA_StatusCode result = UA_Client_readDataTypeAttribute(client->client, nodeId, &dataTypeId);
    
    if (result != UA_STATUSCODE_GOOD) {
        UA_NodeId_clear(&nodeId);
        return NULL;
    }
    
    char* dataTypeStr = NULL;
    
    // Try to get the data type node's browse name
    UA_QualifiedName dataTypeName;
    UA_QualifiedName_init(&dataTypeName);
    result = UA_Client_readBrowseNameAttribute(client->client, dataTypeId, &dataTypeName);
    
    if (result == UA_STATUSCODE_GOOD && dataTypeName.name.length > 0) {
        dataTypeStr = malloc(dataTypeName.name.length + 1);
        if (dataTypeStr) {
            memcpy(dataTypeStr, dataTypeName.name.data, dataTypeName.name.length);
            dataTypeStr[dataTypeName.name.length] = '\0';
        }
        UA_QualifiedName_clear(&dataTypeName);
    } else {
        // Fallback: try to identify common data types by their node IDs
        if (dataTypeId.namespaceIndex == 0 && dataTypeId.identifierType == UA_NODEIDTYPE_NUMERIC) {
            switch (dataTypeId.identifier.numeric) {
                case 1:  dataTypeStr = strdup("Boolean"); break;
                case 2:  dataTypeStr = strdup("SByte"); break;
                case 3:  dataTypeStr = strdup("Byte"); break;
                case 4:  dataTypeStr = strdup("Int16"); break;
                case 5:  dataTypeStr = strdup("UInt16"); break;
                case 6:  dataTypeStr = strdup("Int32"); break;
                case 7:  dataTypeStr = strdup("UInt32"); break;
                case 8:  dataTypeStr = strdup("Int64"); break;
                case 9:  dataTypeStr = strdup("UInt64"); break;
                case 10: dataTypeStr = strdup("Float"); break;
                case 11: dataTypeStr = strdup("Double"); break;
                case 12: dataTypeStr = strdup("String"); break;
                case 13: dataTypeStr = strdup("DateTime"); break;
                case 14: dataTypeStr = strdup("Guid"); break;
                case 15: dataTypeStr = strdup("ByteString"); break;
                case 16: dataTypeStr = strdup("XmlElement"); break;
                case 17: dataTypeStr = strdup("NodeId"); break;
                case 18: dataTypeStr = strdup("ExpandedNodeId"); break;
                case 19: dataTypeStr = strdup("StatusCode"); break;
                case 20: dataTypeStr = strdup("QualifiedName"); break;
                case 21: dataTypeStr = strdup("LocalizedText"); break;
                default: dataTypeStr = strdup("Unknown"); break;
            }
        } else {
            dataTypeStr = strdup("Custom");
        }
    }
    
    UA_NodeId_clear(&nodeId);
    UA_NodeId_clear(&dataTypeId);
    
    return dataTypeStr;
}

// ============================================================================
// Write Operations
// ============================================================================

static bool opcua_write_scalar_value(OpcUaClient_t* client, const char* node_id, const void* value, const UA_DataType* type) {
    if (!client || !client->client || !client->connected || !node_id || !value || !type) {
        return false;
    }

    UA_NodeId nodeId = parse_node_id_robust(node_id);
    if (UA_NodeId_isNull(&nodeId)) {
        return false;
    }

    UA_Variant variant;
    UA_Variant_init(&variant);

    UA_StatusCode setResult = UA_Variant_setScalarCopy(&variant, value, type);
    if (setResult != UA_STATUSCODE_GOOD) {
        UA_Variant_clear(&variant);
        UA_NodeId_clear(&nodeId);
        return false;
    }

    UA_StatusCode writeResult = UA_Client_writeValueAttribute(client->client, nodeId, &variant);

    UA_Variant_clear(&variant);
    UA_NodeId_clear(&nodeId);

    return writeResult == UA_STATUSCODE_GOOD;
}

bool opcua_write_value_bool(OpcUaClient_t* client, const char* node_id, bool value) {
    UA_Boolean uaValue = value ? UA_TRUE : UA_FALSE;
    return opcua_write_scalar_value(client, node_id, &uaValue, &UA_TYPES[UA_TYPES_BOOLEAN]);
}

bool opcua_write_value_int16(OpcUaClient_t* client, const char* node_id, int16_t value) {
    UA_Int16 uaValue = (UA_Int16)value;
    return opcua_write_scalar_value(client, node_id, &uaValue, &UA_TYPES[UA_TYPES_INT16]);
}

bool opcua_write_value_int32(OpcUaClient_t* client, const char* node_id, int32_t value) {
    UA_Int32 uaValue = (UA_Int32)value;
    return opcua_write_scalar_value(client, node_id, &uaValue, &UA_TYPES[UA_TYPES_INT32]);
}

bool opcua_write_value_int64(OpcUaClient_t* client, const char* node_id, int64_t value) {
    UA_Int64 uaValue = (UA_Int64)value;
    return opcua_write_scalar_value(client, node_id, &uaValue, &UA_TYPES[UA_TYPES_INT64]);
}

bool opcua_write_value_uint16(OpcUaClient_t* client, const char* node_id, uint16_t value) {
    UA_UInt16 uaValue = (UA_UInt16)value;
    return opcua_write_scalar_value(client, node_id, &uaValue, &UA_TYPES[UA_TYPES_UINT16]);
}

bool opcua_write_value_uint32(OpcUaClient_t* client, const char* node_id, uint32_t value) {
    UA_UInt32 uaValue = (UA_UInt32)value;
    return opcua_write_scalar_value(client, node_id, &uaValue, &UA_TYPES[UA_TYPES_UINT32]);
}

bool opcua_write_value_uint64(OpcUaClient_t* client, const char* node_id, uint64_t value) {
    UA_UInt64 uaValue = (UA_UInt64)value;
    return opcua_write_scalar_value(client, node_id, &uaValue, &UA_TYPES[UA_TYPES_UINT64]);
}

bool opcua_write_value_float(OpcUaClient_t* client, const char* node_id, float value) {
    UA_Float uaValue = (UA_Float)value;
    return opcua_write_scalar_value(client, node_id, &uaValue, &UA_TYPES[UA_TYPES_FLOAT]);
}

bool opcua_write_value_double(OpcUaClient_t* client, const char* node_id, double value) {
    UA_Double uaValue = (UA_Double)value;
    return opcua_write_scalar_value(client, node_id, &uaValue, &UA_TYPES[UA_TYPES_DOUBLE]);
}

bool opcua_write_value_string(OpcUaClient_t* client, const char* node_id, const char* value) {
    if (!value) {
        return false;
    }
    UA_String uaValue = UA_STRING((char*)value);
    return opcua_write_scalar_value(client, node_id, &uaValue, &UA_TYPES[UA_TYPES_STRING]);
}

// ============================================================================
// Subscription Management
// ============================================================================

static void dataChangeHandler(UA_Client *client, UA_UInt32 subId, void *subContext,
                             UA_UInt32 monId, void *monContext, UA_DataValue *value) {
    if (!monContext || !value) return;
    
    MonitoredItemContext* ctx = (MonitoredItemContext*)monContext;
    
    // Convert value to string according to type
    char* valueStr = NULL;
    UA_Variant *v = &value->value;
    
    if (v->data == NULL) {
        valueStr = strdup("");  // Empty string for NULL values in subscriptions
    } else if (!UA_Variant_isScalar(v)) {
        valueStr = strdup("[Array]");
    } else {
        const UA_DataType* type = v->type;
        // Check both pointer and type ID for robustness
        uint16_t typeId = (type && type->typeId.identifierType == UA_NODEIDTYPE_NUMERIC) ? 
                          type->typeId.identifier.numeric : 0;
        
        if (type == &UA_TYPES[UA_TYPES_DOUBLE] || typeId == 11) {
            valueStr = malloc(64);
            if (valueStr) snprintf(valueStr, 64, "%.6f", *(UA_Double*)v->data);
        } else if (type == &UA_TYPES[UA_TYPES_FLOAT] || typeId == 10) {
            valueStr = malloc(64);
            if (valueStr) snprintf(valueStr, 64, "%.6f", *(UA_Float*)v->data);
        } else if (type == &UA_TYPES[UA_TYPES_INT32] || typeId == 6) {
            valueStr = malloc(32);
            if (valueStr) snprintf(valueStr, 32, "%d", *(UA_Int32*)v->data);
        } else if (type == &UA_TYPES[UA_TYPES_UINT32] || typeId == 7) {
            valueStr = malloc(32);
            if (valueStr) snprintf(valueStr, 32, "%u", *(UA_UInt32*)v->data);
        } else if (type == &UA_TYPES[UA_TYPES_INT16] || typeId == 4) {
            valueStr = malloc(32);
            if (valueStr) snprintf(valueStr, 32, "%d", *(UA_Int16*)v->data);
        } else if (type == &UA_TYPES[UA_TYPES_UINT16] || typeId == 5) {
            valueStr = malloc(32);
            if (valueStr) snprintf(valueStr, 32, "%u", *(UA_UInt16*)v->data);
        } else if (type == &UA_TYPES[UA_TYPES_BYTE]) {
            valueStr = malloc(32);
            if (valueStr) snprintf(valueStr, 32, "%u", *(UA_Byte*)v->data);
        } else if (type == &UA_TYPES[UA_TYPES_SBYTE]) {
            valueStr = malloc(32);
            if (valueStr) snprintf(valueStr, 32, "%d", *(UA_SByte*)v->data);
        } else if (type == &UA_TYPES[UA_TYPES_INT64]) {
            valueStr = malloc(64);
            if (valueStr) snprintf(valueStr, 64, "%lld", (long long)*(UA_Int64*)v->data);
        } else if (type == &UA_TYPES[UA_TYPES_UINT64]) {
            valueStr = malloc(64);
            if (valueStr) snprintf(valueStr, 64, "%llu", (unsigned long long)*(UA_UInt64*)v->data);
        } else if (type == &UA_TYPES[UA_TYPES_BOOLEAN]) {
            valueStr = strdup(*(UA_Boolean*)v->data ? "true" : "false");
        } else if (type == &UA_TYPES[UA_TYPES_STRING] || typeId == 12) {
            UA_String* str = (UA_String*)v->data;
            if (str->length > 0 && str->data) {
                valueStr = malloc(str->length + 1);
                if (valueStr) {
                    memcpy(valueStr, str->data, str->length);
                    valueStr[str->length] = '\0';
                }
            } else {
                valueStr = strdup("");
            }
        } else if (type == &UA_TYPES[UA_TYPES_LOCALIZEDTEXT]) {
            UA_LocalizedText* lt = (UA_LocalizedText*)v->data;
            if (lt->text.length > 0 && lt->text.data) {
                valueStr = malloc(lt->text.length + 1);
                if (valueStr) {
                    memcpy(valueStr, lt->text.data, lt->text.length);
                    valueStr[lt->text.length] = '\0';
                }
            } else {
                valueStr = strdup("");
            }
        } else if (type == &UA_TYPES[UA_TYPES_QUALIFIEDNAME]) {
            UA_QualifiedName* qn = (UA_QualifiedName*)v->data;
            if (qn->name.length > 0 && qn->name.data) {
                valueStr = malloc(qn->name.length + 1);
                if (valueStr) {
                    memcpy(valueStr, qn->name.data, qn->name.length);
                    valueStr[qn->name.length] = '\0';
                }
            } else {
                valueStr = strdup("");
            }
        } else if (type == &UA_TYPES[UA_TYPES_ENUMERATION]) {
            valueStr = malloc(64);
            if (valueStr) snprintf(valueStr, 64, "%d", *(UA_Int32*)v->data);
        } else if (type == &UA_TYPES[UA_TYPES_DATETIME]) {
            valueStr = malloc(64);
            if (valueStr) snprintf(valueStr, 64, "%lld", (long long)*(UA_DateTime*)v->data);
        } else if (type == &UA_TYPES[UA_TYPES_BYTESTRING]) {
            valueStr = strdup("[ByteString]");
        } else {
            valueStr = strdup("");
        }
    }
    
    // Convert timestamp to double (seconds since epoch)
    double timestamp = 0;
    if (value->hasServerTimestamp) {
        timestamp = (double)value->serverTimestamp / UA_DATETIME_SEC;
    } else if (value->hasSourceTimestamp) {
        timestamp = (double)value->sourceTimestamp / UA_DATETIME_SEC;
    } else {
        timestamp = (double)UA_DateTime_now() / UA_DATETIME_SEC;
    }
    
    // Store the value and mark as changed (send even if string is empty)
    if (valueStr) {
        if (ctx->lastValue) {
            free(ctx->lastValue);
        }
        ctx->lastValue = valueStr;
        ctx->lastTimestamp = timestamp;
        ctx->hasChanged = true;
    }
}

// Create a subscription
uint32_t opcua_create_subscription(OpcUaClient_t* client, double publishing_interval) {
    if (!client || !client->client || !client->connected) {
        return 0;
    }
    
    UA_CreateSubscriptionRequest request = UA_CreateSubscriptionRequest_default();
    request.requestedPublishingInterval = (UA_Double)publishing_interval;
    // Keep subscription alive even without changes
    request.requestedLifetimeCount = 10000;
    request.requestedMaxKeepAliveCount = 10;
    
    UA_CreateSubscriptionResponse response = 
        UA_Client_Subscriptions_create(client->client, request, NULL, NULL, NULL);
    
    if (response.responseHeader.serviceResult != UA_STATUSCODE_GOOD) {
        printf("❌ Failed to create subscription: %s\n", 
               UA_StatusCode_name(response.responseHeader.serviceResult));
        UA_CreateSubscriptionResponse_clear(&response);
        return 0;
    }
    
    uint32_t subscriptionId = response.subscriptionId;
    UA_CreateSubscriptionResponse_clear(&response);
    
    printf("✅ Created subscription %u (Interval: %.0f ms)\n", subscriptionId, publishing_interval);
    return subscriptionId;
}

// Delete a subscription
bool opcua_delete_subscription(OpcUaClient_t* client, uint32_t subscription_id) {
    if (!client || !client->client || !client->connected) {
        return false;
    }
    
    UA_StatusCode retval = UA_Client_Subscriptions_deleteSingle(
        client->client, subscription_id);
    
    if (retval != UA_STATUSCODE_GOOD) {
        printf("Failed to delete subscription %u: %s\n", 
               subscription_id, UA_StatusCode_name(retval));
        return false;
    }
    
    // Clean up all monitored items for this client? 
    // Ideally we should match them to subscription, but for now we clear all for this client
    // as we usually have one subscription per client in this simple app.
    if (client->monitoredItems) {
        for (int i = 0; i < client->monitoredItemCount; i++) {
             if (client->monitoredItems[i]) {
                 free(client->monitoredItems[i]->nodeId);
                 free(client->monitoredItems[i]->lastValue);
                 free(client->monitoredItems[i]);
                 client->monitoredItems[i] = NULL;
             }
        }
        client->monitoredItemCount = 0;
    }
    
    printf("Deleted subscription %u\n", subscription_id);
    return true;
}

// Add a monitored item to a subscription
uint32_t opcua_add_monitored_item(OpcUaClient_t* client, uint32_t subscription_id, 
                                  const char* node_id, double sampling_interval) {
    if (!client || !client->client || !client->connected || !node_id) {
        return 0;
    }
    
    // Check capacity
    if (client->monitoredItemCount >= client->monitoredItemCapacity) {
        printf("Maximum monitored items reached for client\n");
        return 0;
    }
    
    // Robust NodeId parsing for monitored items
    UA_NodeId nodeId = parse_node_id_robust(node_id);
    if (UA_NodeId_isNull(&nodeId)) {
        return 0;
    }
    
    // Create the monitored item request
    UA_MonitoredItemCreateRequest monRequest = 
        UA_MonitoredItemCreateRequest_default(nodeId);
    monRequest.requestedParameters.samplingInterval = sampling_interval;
    monRequest.requestedParameters.queueSize = 1; // Latest value only
    monRequest.requestedParameters.discardOldest = true;
    
    // Create context for the callback
    MonitoredItemContext* ctx = malloc(sizeof(MonitoredItemContext));
    if (!ctx) {
        UA_NodeId_clear(&nodeId);
        return 0;
    }
    ctx->nodeId = strdup(node_id);
    ctx->lastValue = NULL;
    ctx->lastTimestamp = 0;
    ctx->hasChanged = false;
    ctx->monitoredItemId = 0;

    int storedIndex = client->monitoredItemCount;
    client->monitoredItems[client->monitoredItemCount++] = ctx;

    UA_MonitoredItemCreateResult monResponse = UA_Client_MonitoredItems_createDataChange(
        client->client, subscription_id,
        UA_TIMESTAMPSTORETURN_BOTH,
        monRequest, ctx, dataChangeHandler, NULL);

    if (monResponse.statusCode != UA_STATUSCODE_GOOD) {
        printf("❌ Failed to monitor %s: %s\n",
               node_id, UA_StatusCode_name(monResponse.statusCode));
        free(ctx->nodeId);
        free(ctx);
        client->monitoredItems[storedIndex] = NULL;
        client->monitoredItemCount--;
        UA_NodeId_clear(&nodeId);
        UA_MonitoredItemCreateResult_clear(&monResponse);
        return 0;
    }

    uint32_t monitoredItemId = monResponse.monitoredItemId;
    ctx->monitoredItemId = monitoredItemId;
    UA_MonitoredItemCreateResult_clear(&monResponse);
    UA_NodeId_clear(&nodeId);

    printf("📡 Monitoring %s (ID: %u)\n", node_id, monitoredItemId);
    return monitoredItemId;
}

// Remove a monitored item
bool opcua_remove_monitored_item(OpcUaClient_t* client, uint32_t subscription_id,
                                 uint32_t monitored_item_id) {
    if (!client || !client->client || !client->connected) {
        return false;
    }

    UA_StatusCode retval = UA_Client_MonitoredItems_deleteSingle(
        client->client, subscription_id, monitored_item_id);

    if (retval != UA_STATUSCODE_GOOD) {
        printf("Failed to delete monitored item %u: %s\n",
               monitored_item_id, UA_StatusCode_name(retval));
        return false;
    }

    // Free the matching context and compact the slot so the capacity-limited
    // array can be reused. open62541 calls the callback on the same thread that
    // runs UA_Client_run_iterate, so this is safe under the Swift-side lock.
    for (int i = 0; i < client->monitoredItemCount; i++) {
        MonitoredItemContext* ctx = client->monitoredItems[i];
        if (ctx && ctx->monitoredItemId == monitored_item_id) {
            free(ctx->nodeId);
            free(ctx->lastValue);
            free(ctx);
            for (int j = i; j < client->monitoredItemCount - 1; j++) {
                client->monitoredItems[j] = client->monitoredItems[j + 1];
            }
            client->monitoredItems[client->monitoredItemCount - 1] = NULL;
            client->monitoredItemCount--;
            break;
        }
    }

    printf("Deleted monitored item %u\n", monitored_item_id);
    return true;
}

// Process subscriptions (should be called periodically)
void opcua_process_subscriptions(OpcUaClient_t* client, int timeout_ms) {
    if (!client || !client->client || !client->connected) {
        return;
    }
    
    // Process any pending publish responses
    UA_StatusCode retval = UA_Client_run_iterate(client->client, (UA_UInt32)timeout_ms);
    
    if (retval != UA_STATUSCODE_GOOD && retval != UA_STATUSCODE_BADTIMEOUT) {
        // printf("Error processing subscriptions: %s\n", UA_StatusCode_name(retval));
    }
}

// Get the latest value for a monitored item
char* opcua_get_monitored_value(OpcUaClient_t* client, const char* node_id) {
    if (!client || !node_id) {
        return NULL;
    }
    
    // Find in CLIENT array
    for (int i = 0; i < client->monitoredItemCount; i++) {
        if (client->monitoredItems[i] && strcmp(client->monitoredItems[i]->nodeId, node_id) == 0) {
            if (client->monitoredItems[i]->lastValue) {
                return strdup(client->monitoredItems[i]->lastValue);
            }
            break;
        }
    }
    
    return NULL;
}

// Get the timestamp of the last value change
double opcua_get_monitored_timestamp(OpcUaClient_t* client, const char* node_id) {
    if (!client || !node_id) {
        return 0;
    }
    
    for (int i = 0; i < client->monitoredItemCount; i++) {
        if (client->monitoredItems[i] && strcmp(client->monitoredItems[i]->nodeId, node_id) == 0) {
            return client->monitoredItems[i]->lastTimestamp;
        }
    }
    
    return 0;
}

// Check if a monitored value has changed since last check
bool opcua_has_value_changed(OpcUaClient_t* client, const char* node_id) {
    if (!client || !node_id) {
        return false;
    }
    
    for (int i = 0; i < client->monitoredItemCount; i++) {
        if (client->monitoredItems[i] && strcmp(client->monitoredItems[i]->nodeId, node_id) == 0) {
            bool changed = client->monitoredItems[i]->hasChanged;
            // Reset the changed flag after checking
            client->monitoredItems[i]->hasChanged = false;
            return changed;
        }
    }
    
    return false;
}
