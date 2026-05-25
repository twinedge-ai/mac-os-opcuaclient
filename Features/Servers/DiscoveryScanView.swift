import SwiftUI

struct DiscoveryScanView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var discoveryEndpoint = ""
    @State private var isScanning = false
    @State private var endpoints: [String] = []
    @State private var errorMessage: String?
    @State private var addedEndpoints: Set<String> = []

    private let discoveryManager = DiscoveryManager()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Discovery Endpoint")
                        .font(.headline)

                    TextField("opc.tcp://localhost:4840", text: $discoveryEndpoint)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 12) {
                        Button(action: scan) {
                            Label("Scan", systemImage: "wifi")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(discoveryEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isScanning)

                        Button("Clear") {
                            endpoints = []
                            errorMessage = nil
                            addedEndpoints.removeAll()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isScanning)

                        Spacer()
                    }
                }
                .padding(.horizontal)

                if isScanning {
                    ProgressView("Scanning for endpoints...")
                        .padding(.horizontal)
                } else if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }

                if endpoints.isEmpty && !isScanning && errorMessage == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No endpoints discovered yet")
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 24)
                } else {
                    List {
                        Section(header: resultsHeader) {
                            ForEach(endpoints, id: \.self) { endpoint in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(endpoint)
                                            .font(.callout)
                                            .lineLimit(2)

                                        if let details = parseEndpoint(endpoint) {
                                            Text("\(details.schema.displayName) • \(details.host):\(details.port)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text("Unsupported endpoint format")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    addButton(for: endpoint)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Scan Network")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if discoveryEndpoint.isEmpty {
                    discoveryEndpoint = defaultDiscoveryEndpoint()
                }
            }
        }
        .frame(minWidth: 500, minHeight: 520)
    }

    private var resultsHeader: some View {
        HStack {
            Text("Discovered Endpoints")
            Spacer()
            Button("Add All") {
                addAllEndpoints()
            }
            .font(.caption)
            .disabled(endpoints.isEmpty || isScanning)
        }
    }

    private func scan() {
        let endpoint = discoveryEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else { return }

        isScanning = true
        errorMessage = nil
        endpoints = []

        Task {
            let results = discoveryManager.fetchEndpoints(from: endpoint)
            endpoints = Array(Set(results)).sorted()
            isScanning = false
            if endpoints.isEmpty {
                errorMessage = "No endpoints found at \(endpoint)"
            }
        }
    }

    @ViewBuilder
    private func addButton(for endpoint: String) -> some View {
        if isKnownEndpoint(endpoint) || addedEndpoints.contains(endpoint) {
            Label("Added", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if parseEndpoint(endpoint) == nil {
            Text("Unsupported")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            Button("Add") {
                addServer(from: endpoint)
            }
            .buttonStyle(.bordered)
            .font(.caption)
        }
    }

    private func addAllEndpoints() {
        for endpoint in endpoints {
            if !isKnownEndpoint(endpoint), parseEndpoint(endpoint) != nil {
                addServer(from: endpoint)
            }
        }
    }

    private func addServer(from endpoint: String) {
        guard let details = parseEndpoint(endpoint) else { return }

        let name = "\(details.host):\(details.port)"
        let server = OPCUAServer(
            name: name,
            networkSchema: details.schema,
            host: details.host,
            port: details.port,
            securityMode: .none,
            authenticationMode: .anonymous,
            description: "Discovered via GetEndpoints"
        )

        appState.saveServer(server)
        addedEndpoints.insert(endpoint)
    }

    private func defaultDiscoveryEndpoint() -> String {
        if let server = appState.servers.first {
            return server.endpoint
        }
        return "opc.tcp://localhost:4840"
    }

    private func isKnownEndpoint(_ endpoint: String) -> Bool {
        guard let details = parseEndpoint(endpoint) else { return false }
        return appState.servers.contains {
            $0.networkSchema == details.schema &&
            $0.host == details.host &&
            $0.port == details.port
        }
    }

    private func parseEndpoint(_ endpoint: String) -> (schema: NetworkSchema, host: String, port: Int)? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        let schema: NetworkSchema
        let rest: String

        if lowercased.hasPrefix("opc.tcp://") {
            schema = .opcTcp
            rest = String(trimmed.dropFirst("opc.tcp://".count))
        } else {
            return nil
        }

        let hostPortPart = rest.split(separator: "/").first ?? Substring(rest)
        let components = hostPortPart.split(separator: ":", maxSplits: 1)
        let host = String(components[0])
        let port = components.count > 1 ? Int(components[1]) ?? schema.defaultPort : schema.defaultPort

        guard !host.isEmpty else { return nil }
        return (schema: schema, host: host, port: port)
    }
}
