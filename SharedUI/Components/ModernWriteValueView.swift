import SwiftUI

struct ModernWriteValueView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    
    let server: OPCUAServer
    let nodeId: String
    let displayName: String
    
    @State private var value: String = ""
    @State private var dataType: String = "String"
    @State private var isWriting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    let dataTypes = ["String", "Int32", "UInt32", "Float", "Double", "Boolean", "Byte"]
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.tertiaryBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Form {
                        Section {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                                Text("Node")
                                    .font(DesignSystem.Typography.caption2)
                                    .foregroundColor(DesignSystem.Colors.tertiaryText)
                                
                                Text(displayName)
                                    .font(DesignSystem.Typography.callout.weight(.medium))
                                
                                Text(nodeId)
                                    .font(DesignSystem.Typography.caption2)
                                    .foregroundColor(DesignSystem.Colors.tertiaryText)
                            }
                            .padding(.vertical, DesignSystem.Spacing.xSmall)
                        }
                        
                        Section("Value to Write") {
                            TextField("Enter value", text: $value)
                                .textFieldStyle(.plain)
                            
                            Picker("Data Type", selection: $dataType) {
                                ForEach(dataTypes, id: \.self) { type in
                                    Text(type).tag(type)
                                }
                            }
                        }
                        
                        if let error = errorMessage {
                            Section {
                                HStack {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(DesignSystem.Colors.error)
                                    Text(error)
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.error)
                                }
                            }
                        }
                        
                        if let success = successMessage {
                            Section {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(DesignSystem.Colors.success)
                                    Text(success)
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.success)
                                }
                            }
                        }
                        
                        Section {
                            Button(action: performWrite) {
                                HStack {
                                    if isWriting {
                                        ProgressView()
                                            .controlSize(.small)
                                            .padding(.trailing, DesignSystem.Spacing.xSmall)
                                    }
                                    Text(isWriting ? "Writing..." : "Write Value")
                                        .font(DesignSystem.Typography.callout.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isWriting || value.isEmpty)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Write Value")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 450)
        #endif
    }
    
    private func performWrite() {
        guard !value.isEmpty else { return }
        
        isWriting = true
        errorMessage = nil
        successMessage = nil
        
        Task {
            let success = await appState.connectionManager.writeNodeValue(
                for: server,
                nodeId: nodeId,
                value: value,
                dataType: dataType,
                nodeDisplayName: displayName
            )
            
            await MainActor.run {
                isWriting = false
                if success {
                    successMessage = "Value written successfully"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                } else {
                    errorMessage = "Failed to write value. Check the data type and connection."
                }
            }
        }
    }
}

struct WriteValueView_Previews: PreviewProvider {
    static var previews: some View {
        ModernWriteValueView(
            server: OPCUAServer(
                name: "Test Server",
                endpoint: "localhost",
                port: 4840,
                securityMode: .none,
                authenticationMode: .anonymous
            ),
            nodeId: "ns=2;i=1",
            displayName: "Sensors.Temperature"
        )
        .environmentObject(AppState())
    }
}
