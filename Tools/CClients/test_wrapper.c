#include "OpcUaWrapper.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    printf("🔧 Testing OPC UA C wrapper...\n");
    
    // Create client
    OpcUaClient_t* client = opcua_client_create();
    if (!client) {
        printf("❌ Failed to create client\n");
        return 1;
    }
    
    printf("✅ Client created successfully\n");
    
    // Connect to server
    const char* endpoint = "opc.tcp://localhost:10000";
    printf("🔗 Connecting to %s...\n", endpoint);
    
    bool connected = opcua_client_connect(client, endpoint);
    if (!connected) {
        printf("❌ Failed to connect\n");
        opcua_client_destroy(client);
        return 1;
    }
    
    printf("✅ Connected successfully!\n");
    
    // Browse address space
    printf("📁 Browsing address space...\n");
    OpcUaNodeList_t* nodeList = opcua_browse_root(client);
    if (!nodeList) {
        printf("❌ Failed to browse\n");
        opcua_client_disconnect(client);
        opcua_client_destroy(client);
        return 1;
    }

    int nodeCount = opcua_node_list_count(nodeList);
    printf("📄 Found %d nodes:\n", nodeCount);
    for (int i = 0; i < nodeCount; i++) {
        const char* id = opcua_node_get_id(nodeList, i);
        const char* name = opcua_node_get_name(nodeList, i);
        const char* display = opcua_node_get_display_name(nodeList, i);
        const char* class = opcua_node_get_class(nodeList, i);
        
        printf("  %d. %s (%s) - %s [%s]\n", i+1, 
               display ? display : "Unknown",
               name ? name : "Unknown", 
               id ? id : "Unknown",
               class ? class : "Unknown");
        
        // Try to read value if it's a TestVariable
        if (id && strstr(id, "TestVariable")) {
            double value;
            if (opcua_read_value_double(client, id, &value)) {
                printf("     📖 Value: %.2f\n", value);
            }
        }
    }
    
    // Cleanup
    opcua_node_list_destroy(nodeList);

    opcua_client_disconnect(client);
    opcua_client_destroy(client);
    
    printf("✅ Test completed successfully!\n");
    return 0;
}
