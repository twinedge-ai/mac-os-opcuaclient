#!/usr/bin/env swift

import Foundation
import SwiftData

@Model
final class TestServer {
    var id: UUID
    var name: String
    
    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

// Set up the model container
let schema = Schema([TestServer.self])
let modelConfiguration = ModelConfiguration("TestStore", schema: schema, isStoredInMemoryOnly: false)

do {
    let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
    let context = container.mainContext
    
    // Test saving
    let server = TestServer(name: "Test Server \(Date())")
    context.insert(server)
    try context.save()
    print("✅ Saved server: \(server.name)")
    
    // Test loading
    let descriptor = FetchDescriptor<TestServer>()
    let servers = try context.fetch(descriptor)
    print("📂 Found \(servers.count) servers in database:")
    for s in servers {
        print("  - \(s.name)")
    }
} catch {
    print("❌ Error: \(error)")
}