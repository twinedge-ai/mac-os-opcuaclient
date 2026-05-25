#!/usr/bin/env python3

"""
Simple OPC UA client to test our server on port 10000
"""

try:
    from opcua import Client
except ImportError:
    print("❌ opcua library not found. Install with: pip install opcua")
    exit(1)

def main():
    # Connect to our test server
    url = "opc.tcp://localhost:10000"
    
    print(f"🔗 Connecting to OPC UA server at {url}")
    
    client = Client(url)
    
    try:
        client.connect()
        print("✅ Connected successfully!")
        
        # Get root node
        print("📁 Browsing root folder...")
        root = client.get_root_node()
        print(f"Root node: {root}")
        
        # Browse Objects folder
        objects = client.get_objects_node()
        print(f"Objects node: {objects}")
        
        # Get all children of Objects folder
        children = objects.get_children()
        print(f"📄 Found {len(children)} children in Objects folder:")
        
        for child in children:
            try:
                browse_name = child.get_browse_name()
                display_name = child.get_display_name()
                node_id = child.nodeid
                node_class = child.get_node_class()
                print(f"  - {display_name.Text} (Browse: {browse_name.Name}) - ID: {node_id} - Class: {node_class}")
                
                # Try to read value if it's a variable
                if hasattr(child, 'get_value'):
                    try:
                        value = child.get_value()
                        print(f"    Value: {value}")
                    except Exception as e:
                        print(f"    (Could not read value: {e})")
                        
            except Exception as e:
                print(f"  - Error reading node: {e}")
        
        # Look for our test variable specifically
        print("\n🔍 Looking for TestVariable...")
        try:
            # Try to find our test variable with node ID ns=1;s=TestVariable
            test_var = client.get_node("ns=1;s=TestVariable")
            print(f"Found TestVariable: {test_var}")
            value = test_var.get_value()
            print(f"TestVariable value: {value}")
        except Exception as e:
            print(f"Could not find TestVariable: {e}")
        
    except Exception as e:
        print(f"❌ Connection failed: {e}")
    finally:
        client.disconnect()
        print("🔌 Disconnected")

if __name__ == "__main__":
    main()