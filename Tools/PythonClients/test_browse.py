#!/usr/bin/env python3
"""Test OPC UA address space browsing"""

from opcua import Client, ua
import time

def test_browse():
    client = Client("opc.tcp://localhost:4840")
    try:
        client.connect()
        print("✅ Connected to OPC UA server")
        
        # Browse from Objects folder (i=84)
        objects = client.get_objects_node()
        print(f"📁 Objects folder: {objects}")
        
        children = objects.get_children()
        print(f"📁 Found {len(children)} children:")
        
        for child in children:
            print(f"  - {child.get_display_name().Text} ({child.nodeid})")
            
        # Test hierarchical browse
        server_node = client.get_server_node() 
        server_children = server_node.get_children()
        print(f"\n📁 Server node children ({len(server_children)}):")
        for child in server_children[:5]:  # First 5 only
            print(f"  - {child.get_display_name().Text} ({child.nodeid})")
            
    except Exception as e:
        print(f"❌ Error: {e}")
    finally:
        client.disconnect()
        print("🔌 Disconnected")

if __name__ == "__main__":
    test_browse()
