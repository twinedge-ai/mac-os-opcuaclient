import Foundation

// Simple test to trigger browse functionality
@main
struct TestBrowseConnection {
    static func main() async {
        print("🧪 Starting browse functionality test...")
        
        // Create a test server
        let testServer = OPCUAServer(
            name: "Test Server",
            endpoint: "localhost",
            port: 4840,
            description: "Test OPC UA server for debugging"
        )
        
        print("📡 Test server created: \(testServer.endpoint):\(testServer.port)")
        
        // Create connection manager
        let connectionManager = OPCUAConnectionManager()
        
        print("🔗 Attempting connection...")
        let connected = await connectionManager.connectToServer(testServer)
        
        if connected {
            print("✅ Connected successfully!")
            
            print("📁 Starting address space browse...")
            let nodes = await connectionManager.browseAddressSpace(for: testServer)
            
            print("📋 Browse returned \(nodes.count) nodes:")
            for node in nodes {
                print("  - \(node.nodeId): \(node.displayName) (\(node.nodeClass))")
            }
            
            print("🔍 Testing specific node read...")
            if let firstNode = nodes.first {
                let value = await connectionManager.readNodeValue(for: testServer, nodeId: firstNode.nodeId)
                print("📖 Read value from \(firstNode.nodeId): \(value ?? "nil")")
            }
            
            print("📤 Disconnecting...")
            connectionManager.disconnectFromServer(testServer)
        } else {
            print("❌ Connection failed")
            if let error = connectionManager.getLastError(for: testServer) {
                print("   Error: \(error)")
            }
        }
        
        print("🧪 Test completed")
    }
}