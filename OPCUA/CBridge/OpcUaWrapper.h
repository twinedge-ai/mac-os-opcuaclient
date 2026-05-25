//
//  OpcUaWrapper.h
//  OpcUaClient
//

#ifndef OpcUaWrapper_h
#define OpcUaWrapper_h

#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>

// Opaque pointer types for Swift
typedef struct OpcUaClient_t OpcUaClient_t;
typedef struct OpcUaNodeList_t OpcUaNodeList_t;
typedef struct OpcUaEndpointList_t OpcUaEndpointList_t;

// Simple C interface for Swift
OpcUaClient_t* opcua_client_create(void);
void opcua_client_destroy(OpcUaClient_t* client);

bool opcua_client_connect(OpcUaClient_t* client, const char* endpoint);
bool opcua_client_connect_username(OpcUaClient_t* client, const char* endpoint, const char* username, const char* password);
void opcua_client_disconnect(OpcUaClient_t* client);

// Browse functions - returns node list handle
OpcUaNodeList_t* opcua_browse_root(OpcUaClient_t* client);
OpcUaNodeList_t* opcua_browse_node(OpcUaClient_t* client, const char* node_id);
int opcua_read_value_double(OpcUaClient_t* client, const char* node_id, double* value);

// New generic value reading function that returns values as strings
char* opcua_read_value_string(OpcUaClient_t* client, const char* node_id);
void opcua_free_string(char* str);

// Read the data type attribute of a node
char* opcua_read_datatype(OpcUaClient_t* client, const char* node_id);

// Configure security policy, message security mode, and client certificates
bool opcua_client_configure_security(
    OpcUaClient_t* client,
    const char* security_policy,
    int security_mode,
    const char* client_cert_path,
    const char* client_key_path,
    const char* server_cert_path
);
bool opcua_client_configure_certificate_auth(
    OpcUaClient_t* client,
    const char* client_cert_path,
    const char* client_key_path
);

// Discovery / endpoint lookup
OpcUaEndpointList_t* opcua_get_endpoints(const char* endpoint);
int opcua_endpoint_list_count(OpcUaEndpointList_t* list);
const char* opcua_endpoint_get(OpcUaEndpointList_t* list, int index);
void opcua_endpoint_list_destroy(OpcUaEndpointList_t* list);

// Write operations for common scalar types
bool opcua_write_value_bool(OpcUaClient_t* client, const char* node_id, bool value);
bool opcua_write_value_int16(OpcUaClient_t* client, const char* node_id, int16_t value);
bool opcua_write_value_int32(OpcUaClient_t* client, const char* node_id, int32_t value);
bool opcua_write_value_int64(OpcUaClient_t* client, const char* node_id, int64_t value);
bool opcua_write_value_uint16(OpcUaClient_t* client, const char* node_id, uint16_t value);
bool opcua_write_value_uint32(OpcUaClient_t* client, const char* node_id, uint32_t value);
bool opcua_write_value_uint64(OpcUaClient_t* client, const char* node_id, uint64_t value);
bool opcua_write_value_float(OpcUaClient_t* client, const char* node_id, float value);
bool opcua_write_value_double(OpcUaClient_t* client, const char* node_id, double value);
bool opcua_write_value_string(OpcUaClient_t* client, const char* node_id, const char* value);

// Subscription management
uint32_t opcua_create_subscription(OpcUaClient_t* client, double publishing_interval);
bool opcua_delete_subscription(OpcUaClient_t* client, uint32_t subscription_id);
uint32_t opcua_add_monitored_item(OpcUaClient_t* client, uint32_t subscription_id, const char* node_id, double sampling_interval);
bool opcua_remove_monitored_item(OpcUaClient_t* client, uint32_t subscription_id, uint32_t monitored_item_id);
void opcua_process_subscriptions(OpcUaClient_t* client, int timeout_ms);

// Get latest value for a monitored item (used for polling approach)
char* opcua_get_monitored_value(OpcUaClient_t* client, const char* node_id);
double opcua_get_monitored_timestamp(OpcUaClient_t* client, const char* node_id);
bool opcua_has_value_changed(OpcUaClient_t* client, const char* node_id);

// Node list functions
int opcua_node_list_count(OpcUaNodeList_t* list);
const char* opcua_node_get_id(OpcUaNodeList_t* list, int index);
const char* opcua_node_get_name(OpcUaNodeList_t* list, int index);
const char* opcua_node_get_display_name(OpcUaNodeList_t* list, int index);
const char* opcua_node_get_class(OpcUaNodeList_t* list, int index);

// Cleanup
void opcua_node_list_destroy(OpcUaNodeList_t* list);

#endif /* OpcUaWrapper_h */
