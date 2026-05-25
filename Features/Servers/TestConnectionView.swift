import SwiftUI

struct TestConnectionView: View {
    @State private var client = SimpleOpcUaClient()
    @State private var isConnected = false
    @State private var nodes: [SimpleOPCUANode] = []
    @State private var connectionStatus = "Disconnected"
    @State private var endpoint = "opc.tcp://localhost:10000"
    @State private var isLoading = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("OPC UA Client - Address Space Browser")
                .font(.title)
                .fontWeight(.bold)
            
            // Connection Section
            GroupBox("Connection") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Endpoint:")
                        TextField("opc.tcp://localhost:10000", text: $endpoint)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    HStack {
                        Text("Status:")
                        Text(connectionStatus)
                            .foregroundColor(isConnected ? .green : .red)
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Button(isConnected ? "Disconnect" : "Connect") {
                            if isConnected {
                                disconnect()
                            } else {
                                connect()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoading)
                        
                        if isConnected {
                            Button("Browse Address Space") {
                                browseRoot()
                            }
                            .buttonStyle(.bordered)
                            .disabled(isLoading)
                        }
                    }
                }
                .padding()
            }
            
            // Browse Results Section
            if !nodes.isEmpty {
                GroupBox("Address Space") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(nodes) { node in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(node.displayName)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Text(node.nodeClass)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.2))
                                            .cornerRadius(4)
                                    }
                                    
                                    Text("Browse Name: \(node.browseName)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text("Node ID: \(node.nodeId)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if let value = node.value {
                                        Text("Value: \(String(describing: value))")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                            .fontWeight(.medium)
                                    }
                                }
                                .padding(.vertical, 4)
                                Divider()
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 400)
                }
            }
            
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Processing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func connect() {
        isLoading = true
        connectionStatus = "Connecting..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            let success = client.connect(to: endpoint)
            
            DispatchQueue.main.async {
                isConnected = success
                connectionStatus = success ? "Connected" : "Connection Failed"
                isLoading = false
                
                if success {
                    print("✅ Connected to \(endpoint)")
                } else {
                    print("❌ Failed to connect to \(endpoint)")
                }
            }
        }
    }
    
    private func disconnect() {
        client.disconnect()
        isConnected = false
        connectionStatus = "Disconnected"
        nodes.removeAll()
    }
    
    private func browseRoot() {
        guard isConnected else { return }
        
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let browseNodes = client.browseRootFolder()
            
            // Try to read values for Variable nodes
            var nodesWithValues = browseNodes
            for (index, node) in browseNodes.enumerated() {
                if node.nodeClass == "Variable" && node.nodeId.contains("TestVariable") {
                    if let value = client.readDoubleValue(nodeId: node.nodeId) {
                        nodesWithValues[index].value = value
                        print("📖 Read value from \(node.nodeId): \(value)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                nodes = nodesWithValues
                isLoading = false
                print("📁 Found \(nodes.count) nodes in address space")
                
                // Log summary
                let variableCount = nodes.filter { $0.nodeClass == "Variable" }.count
                let objectCount = nodes.filter { $0.nodeClass == "Object" }.count
                print("📊 Summary: \(variableCount) variables, \(objectCount) objects")
            }
        }
    }
}

#Preview {
    TestConnectionView()
}