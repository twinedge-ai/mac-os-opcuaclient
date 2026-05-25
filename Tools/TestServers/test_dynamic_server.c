#include <open62541/server.h>
#include <open62541/server_config_default.h>
#include <signal.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <unistd.h>

UA_Boolean running = true;
static void stopHandler(int sig) {
    running = false;
}

int main(void) {
    signal(SIGINT, stopHandler);
    signal(SIGTERM, stopHandler);

    UA_Server *server = UA_Server_new();
    if(!server) {
        fprintf(stderr, "Failed to allocate OPC UA server\n");
        return EXIT_FAILURE;
    }
    UA_ServerConfig *config = UA_Server_getConfig(server);
    
    /* Set custom port 10001 */
    UA_ServerConfig_setMinimal(config, 10001, NULL);
    
    /* Add variables with dynamic values */
    UA_NodeId flowRateId;
    UA_VariableAttributes attr = UA_VariableAttributes_default;
    UA_Double flowRate = 50.0;
    UA_Variant_setScalar(&attr.value, &flowRate, &UA_TYPES[UA_TYPES_DOUBLE]);
    attr.description = UA_LOCALIZEDTEXT("en-US", "Flow Rate in L/min");
    attr.displayName = UA_LOCALIZEDTEXT("en-US", "Flow Rate");
    attr.dataType = UA_TYPES[UA_TYPES_DOUBLE].typeId;
    attr.accessLevel = UA_ACCESSLEVELMASK_READ | UA_ACCESSLEVELMASK_WRITE;

    UA_QualifiedName flowRateName = UA_QUALIFIEDNAME(1, "FlowRate");
    UA_NodeId parentNodeId = UA_NODEID_NUMERIC(0, UA_NS0ID_OBJECTSFOLDER);
    UA_NodeId parentReferenceNodeId = UA_NODEID_NUMERIC(0, UA_NS0ID_ORGANIZES);
    
    UA_Server_addVariableNode(server, UA_NODEID_STRING(1, "FlowRate"),
                              parentNodeId, parentReferenceNodeId, flowRateName,
                              UA_NODEID_NUMERIC(0, UA_NS0ID_BASEDATAVARIABLETYPE),
                              attr, NULL, &flowRateId);

    /* Add voltage variable */
    UA_NodeId voltageId;
    UA_VariableAttributes voltageAttr = UA_VariableAttributes_default;
    UA_Double voltage = 220.0;
    UA_Variant_setScalar(&voltageAttr.value, &voltage, &UA_TYPES[UA_TYPES_DOUBLE]);
    voltageAttr.description = UA_LOCALIZEDTEXT("en-US", "Voltage in Volts");
    voltageAttr.displayName = UA_LOCALIZEDTEXT("en-US", "Voltage");
    voltageAttr.dataType = UA_TYPES[UA_TYPES_DOUBLE].typeId;
    voltageAttr.accessLevel = UA_ACCESSLEVELMASK_READ | UA_ACCESSLEVELMASK_WRITE;

    UA_QualifiedName voltageName = UA_QUALIFIEDNAME(1, "Voltage");
    UA_Server_addVariableNode(server, UA_NODEID_STRING(1, "Voltage"),
                              parentNodeId, parentReferenceNodeId, voltageName,
                              UA_NODEID_NUMERIC(0, UA_NS0ID_BASEDATAVARIABLETYPE),
                              voltageAttr, NULL, &voltageId);

    /* Add temperature variable */
    UA_NodeId tempId;
    UA_VariableAttributes tempAttr = UA_VariableAttributes_default;
    UA_Double temperature = 25.0;
    UA_Variant_setScalar(&tempAttr.value, &temperature, &UA_TYPES[UA_TYPES_DOUBLE]);
    tempAttr.description = UA_LOCALIZEDTEXT("en-US", "Temperature in Celsius");
    tempAttr.displayName = UA_LOCALIZEDTEXT("en-US", "Temperature");
    tempAttr.dataType = UA_TYPES[UA_TYPES_DOUBLE].typeId;
    tempAttr.accessLevel = UA_ACCESSLEVELMASK_READ | UA_ACCESSLEVELMASK_WRITE;

    UA_QualifiedName tempName = UA_QUALIFIEDNAME(1, "Temperature");
    UA_Server_addVariableNode(server, UA_NODEID_STRING(1, "Temperature"),
                              parentNodeId, parentReferenceNodeId, tempName,
                              UA_NODEID_NUMERIC(0, UA_NS0ID_BASEDATAVARIABLETYPE),
                              tempAttr, NULL, &tempId);

    /* Add pressure variable */
    UA_NodeId pressureId;
    UA_VariableAttributes pressureAttr = UA_VariableAttributes_default;
    UA_Double pressure = 100.0;
    UA_Variant_setScalar(&pressureAttr.value, &pressure, &UA_TYPES[UA_TYPES_DOUBLE]);
    pressureAttr.description = UA_LOCALIZEDTEXT("en-US", "Pressure in kPa");
    pressureAttr.displayName = UA_LOCALIZEDTEXT("en-US", "Pressure");
    pressureAttr.dataType = UA_TYPES[UA_TYPES_DOUBLE].typeId;
    pressureAttr.accessLevel = UA_ACCESSLEVELMASK_READ | UA_ACCESSLEVELMASK_WRITE;

    UA_QualifiedName pressureName = UA_QUALIFIEDNAME(1, "Pressure");
    UA_Server_addVariableNode(server, UA_NODEID_STRING(1, "Pressure"),
                              parentNodeId, parentReferenceNodeId, pressureName,
                              UA_NODEID_NUMERIC(0, UA_NS0ID_BASEDATAVARIABLETYPE),
                              pressureAttr, NULL, &pressureId);

    printf("✅ Starting dynamic OPC UA test server on opc.tcp://localhost:10001\n");
    printf("📊 Variables: FlowRate, Voltage, Temperature, Pressure\n");
    printf("🔄 Values update every second\n");
    printf("Press Ctrl+C to stop\n\n");

    UA_StatusCode retval = UA_Server_run_startup(server);
    if(retval != UA_STATUSCODE_GOOD) {
        UA_Server_delete(server);
        return (int)retval;
    }

    int counter = 0;
    while(running) {
        /* Update values with realistic patterns */
        counter++;
        
        /* Flow rate: oscillates between 40 and 60 L/min */
        flowRate = 50.0 + 10.0 * sin(counter * 0.1);
        UA_Variant flowValue;
        UA_Variant_setScalar(&flowValue, &flowRate, &UA_TYPES[UA_TYPES_DOUBLE]);
        UA_Server_writeValue(server, flowRateId, flowValue);

        /* Voltage: small fluctuations around 220V */
        voltage = 220.0 + (rand() % 10 - 5) * 0.5;
        UA_Variant voltValue;
        UA_Variant_setScalar(&voltValue, &voltage, &UA_TYPES[UA_TYPES_DOUBLE]);
        UA_Server_writeValue(server, voltageId, voltValue);

        /* Temperature: gradual increase with noise */
        temperature = 25.0 + counter * 0.01 + (rand() % 10 - 5) * 0.1;
        UA_Variant tempValue;
        UA_Variant_setScalar(&tempValue, &temperature, &UA_TYPES[UA_TYPES_DOUBLE]);
        UA_Server_writeValue(server, tempId, tempValue);

        /* Pressure: oscillates with different frequency */
        pressure = 100.0 + 5.0 * sin(counter * 0.05);
        UA_Variant pressValue;
        UA_Variant_setScalar(&pressValue, &pressure, &UA_TYPES[UA_TYPES_DOUBLE]);
        UA_Server_writeValue(server, pressureId, pressValue);

        if(counter % 10 == 0) {
            printf("📊 Updated values - Flow: %.2f L/min, Voltage: %.1f V, Temp: %.1f°C, Pressure: %.1f kPa\n", 
                   flowRate, voltage, temperature, pressure);
        }

        UA_Server_run_iterate(server, true);
        usleep(100000); /* Update every 100ms for smoother changes */
    }

    UA_Server_run_shutdown(server);
    UA_Server_delete(server);
    return 0;
}
