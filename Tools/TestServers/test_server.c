#include <open62541/server.h>
#include <open62541/server_config_default.h>
#include <open62541/plugin/log_stdout.h>

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>

UA_Boolean running = true;

static void stopHandler(int sig) {
    UA_LOG_INFO(UA_Log_Stdout, UA_LOGCATEGORY_SERVER, "received ctrl-c");
    running = false;
}

int main() {
    signal(SIGINT, stopHandler);
    signal(SIGTERM, stopHandler);

    UA_Server *server = UA_Server_new();
    if(!server) {
        fprintf(stderr, "Failed to allocate OPC UA server\n");
        return EXIT_FAILURE;
    }
    UA_ServerConfig *config = UA_Server_getConfig(server);
    UA_ServerConfig_setMinimal(config, 10000, NULL);

    /* Add a variable node to the address space */
    UA_VariableAttributes attr = UA_VariableAttributes_default;
    attr.description = UA_LOCALIZEDTEXT("en-US","Temperature");
    attr.displayName = UA_LOCALIZEDTEXT("en-US","Temperature");
    attr.dataType = UA_TYPES[UA_TYPES_DOUBLE].typeId;
    attr.accessLevel = UA_ACCESSLEVELMASK_READ | UA_ACCESSLEVELMASK_WRITE;

    UA_Double myDouble = 20.5;
    UA_Variant_setScalar(&attr.value, &myDouble, &UA_TYPES[UA_TYPES_DOUBLE]);
    attr.value.storageType = UA_VARIANT_DATA_NODELETE; /* do not free the integer on deletion */

    UA_NodeId myDoubleNodeId = UA_NODEID_STRING(1, "the.answer");
    UA_QualifiedName myDoubleName = UA_QUALIFIEDNAME(1, "the answer");
    UA_NodeId parentNodeId = UA_NODEID_NUMERIC(0, UA_NS0ID_OBJECTSFOLDER);
    UA_NodeId parentReferenceNodeId = UA_NODEID_NUMERIC(0, UA_NS0ID_ORGANIZES);
    UA_Server_addVariableNode(server, myDoubleNodeId, parentNodeId,
                              parentReferenceNodeId, myDoubleName,
                              UA_NODEID_NUMERIC(0, UA_NS0ID_BASEDATAVARIABLETYPE),
                              attr, NULL, NULL);

    printf("✅ OPC UA Server starting on opc.tcp://localhost:10000\n");
    printf("📊 Added variable: 'the.answer' = 20.5\n");
    printf("Press Ctrl+C to stop\n");

    UA_StatusCode retval = UA_Server_run(server, &running);

    UA_Server_delete(server);
    return retval == UA_STATUSCODE_GOOD ? EXIT_SUCCESS : EXIT_FAILURE;
}
