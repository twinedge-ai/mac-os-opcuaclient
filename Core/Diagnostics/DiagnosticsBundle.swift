import Foundation

struct DiagnosticsBundleManifest: Codable {
    let generatedAt: Date
    let appVersion: String
    let serverCount: Int
    let connectedServerCount: Int
    let logCount: Int
    let packetCount: Int
}

enum DiagnosticsBundleExporter {
    @MainActor
    static func export(appState: AppState, diagnostics: DiagnosticsManager) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OPC-UA-Client-Diagnostics-\(ISO8601DateFormatter().string(from: Date()))", isDirectory: true)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let connectedCount = appState.servers.filter { appState.connectionManager.isConnected(to: $0) }.count
        let manifest = DiagnosticsBundleManifest(
            generatedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Debug",
            serverCount: appState.servers.count,
            connectedServerCount: connectedCount,
            logCount: diagnostics.logs.count,
            packetCount: diagnostics.packets.count
        )

        let redactor = DiagnosticsExportRedactor(servers: appState.servers)

        try writeJSON(manifest, to: root.appendingPathComponent("manifest.json"))
        try writeJSON(appState.servers.map(ServerDiagnosticsSnapshot.init(server:)), to: root.appendingPathComponent("servers.json"))
        try writeJSON(diagnostics.logs.map { DiagnosticsLogSnapshot(entry: $0, redactor: redactor) }, to: root.appendingPathComponent("logs.json"))
        try writeJSON(diagnostics.packets.map(DiagnosticsPacketSnapshot.init(packet:)), to: root.appendingPathComponent("packets.json"))

        return root
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}

private struct ServerDiagnosticsSnapshot: Codable {
    let id: UUID
    let name: String
    let endpoint: String
    let securityMode: String
    let securityPolicy: String
    let authenticationMode: String
    let profileCategory: String
    let reconnectPolicy: String
    let trustBehavior: String

    init(server: OPCUAServer) {
        id = server.id
        name = server.name
        // Redact host before export. Diagnostics bundles are routinely attached
        // to bug reports; internal industrial hostnames/IPs are reconnaissance
        // data. Keep scheme + port so the report is still actionable.
        endpoint = "\(server.networkSchema.prefix)[redacted]:\(server.port)"
        securityMode = server.securityMode.rawValue
        securityPolicy = server.securityPolicy.rawValue
        authenticationMode = server.authenticationMode.rawValue
        profileCategory = server.profileCategory.rawValue
        reconnectPolicy = server.reconnectPolicy.rawValue
        trustBehavior = server.trustBehavior.rawValue
    }
}

private struct DiagnosticsLogSnapshot: Codable {
    let timestamp: Date
    let level: String
    let component: String
    let message: String

    init(entry: LogEntry, redactor: DiagnosticsExportRedactor) {
        timestamp = entry.timestamp
        level = entry.level.rawValue
        component = entry.component
        message = redactor.redact(entry.message)
    }
}

private struct DiagnosticsExportRedactor {
    private let servers: [OPCUAServer]
    private let endpointPattern = try? NSRegularExpression(
        pattern: #"\bopc\.(?:tcp|wss)://[^\s,;)\]]+"#,
        options: [.caseInsensitive]
    )

    init(servers: [OPCUAServer]) {
        self.servers = servers
    }

    func redact(_ message: String) -> String {
        var redacted = redactEndpointURLs(in: message)

        for host in knownHosts {
            redacted = redacted.replacingOccurrences(of: host, with: "[redacted-host]")
        }

        return redacted
    }

    private var knownHosts: [String] {
        let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]
        return Array(Set(servers.map(\.host)))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !localHosts.contains($0.lowercased()) }
            .sorted { $0.count > $1.count }
    }

    private func redactEndpointURLs(in message: String) -> String {
        guard let endpointPattern else {
            return message
        }

        var redacted = message
        let nsMessage = message as NSString
        let matches = endpointPattern.matches(
            in: message,
            range: NSRange(location: 0, length: nsMessage.length)
        )

        for match in matches.reversed() {
            let literal = nsMessage.substring(with: match.range)
            guard let range = Range(match.range, in: redacted) else {
                continue
            }
            redacted.replaceSubrange(range, with: redactedEndpointLiteral(literal))
        }

        return redacted
    }

    private func redactedEndpointLiteral(_ literal: String) -> String {
        var endpoint = literal
        var trailingPunctuation = ""
        while let last = endpoint.last, [".", ":"].contains(last) {
            trailingPunctuation.insert(last, at: trailingPunctuation.startIndex)
            endpoint.removeLast()
        }

        guard let url = URL(string: endpoint),
              let scheme = url.scheme else {
            return "[redacted-endpoint]\(trailingPunctuation)"
        }

        let portSuffix = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://[redacted]\(portSuffix)\(trailingPunctuation)"
    }
}

private struct DiagnosticsPacketSnapshot: Codable {
    let timestamp: Date
    let direction: String
    let type: String
    let size: Int
    // Note: PacketInfo.hexDump is intentionally not exported. For SecurityMode
    // = None the first 32 bytes of an OPC UA MSG frame can contain nodeId
    // fragments and primitive values in plaintext. Hex dumps remain visible in
    // the live Diagnostics view but are excluded from shareable exports.

    init(packet: PacketInfo) {
        timestamp = packet.timestamp
        direction = packet.direction == .sent ? "sent" : "received"
        type = packet.type
        size = packet.size
    }
}
