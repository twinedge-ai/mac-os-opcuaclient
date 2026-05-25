import SwiftUI

struct SecurityWorkspaceView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var certificateManager = CertificateManager.shared
    @State private var selectedSection = SecuritySection.applicationCertificate

    init(selectedItemID: String? = nil) {
        _selectedSection = State(initialValue: selectedItemID.flatMap(SecuritySection.init(rawValue:)) ?? .applicationCertificate)
    }

    static let sidebarItems: [EnterpriseWorkspaceItem] = SecuritySection.allCases.map {
        EnterpriseWorkspaceItem(
            id: $0.rawValue,
            title: $0.title,
            subtitle: $0.subtitle,
            systemImage: $0.systemImage,
            tint: $0.tint
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            SecurityHeader(connectedServers: connectedServers, weakProfiles: weakProfiles)

            HStack(spacing: 0) {
                List(SecuritySection.allCases, selection: $selectedSection) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
                .listStyle(.sidebar)
                .frame(minWidth: 190, idealWidth: 220, maxWidth: 260)

                Divider()

                securityContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Security")
    }

    private var connectedServers: Int {
        appState.servers.filter { appState.connectionManager.isConnected(to: $0) }.count
    }

    private var weakProfiles: [OPCUAServer] {
        appState.servers.filter { $0.securityMode == .none || $0.securityPolicy == .none || $0.securityPolicy.isDeprecated }
    }

    @ViewBuilder
    private var securityContent: some View {
        switch selectedSection {
        case .applicationCertificate:
            CertificateInventoryView(
                title: "Application Certificate",
                certificates: certificateManager.userCertificates,
                emptyMessage: "No application or user certificates have been generated or imported."
            )
        case .trustedServers:
            SecurityTablePlaceholder(
                title: "Pinned Server Certificates",
                rows: pinnedServerCertificateRows
            )
        case .rejectedCertificates:
            SecurityTablePlaceholder(
                title: "Rejected Certificates",
                rows: [
                    SecurityTableRow(field: "Trust store", value: "No shared rejected-certificate store is active"),
                    SecurityTableRow(field: "Connection behavior", value: "Secure profiles require a selected server certificate")
                ]
            )
        case .userCertificates:
            CertificateInventoryView(
                title: "User Certificates",
                certificates: certificateManager.userCertificates,
                emptyMessage: "Import or generate user certificates for certificate authentication."
            )
        case .securityPolicies:
            SecurityPolicyPostureView(servers: appState.servers)
        case .auditLog:
            SecurityAuditLogView()
        }
    }

    private var pinnedServerCertificateRows: [SecurityTableRow] {
        let rows = appState.servers.compactMap { server -> SecurityTableRow? in
            guard let path = server.serverCertificatePath,
                  !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return SecurityTableRow(field: server.name, value: (path as NSString).lastPathComponent)
        }

        if rows.isEmpty {
            return [
                SecurityTableRow(field: "Pinned profiles", value: "No secure profile has a selected server certificate")
            ]
        }

        return rows
    }
}

private enum SecuritySection: String, CaseIterable, Identifiable {
    case applicationCertificate
    case trustedServers
    case rejectedCertificates
    case userCertificates
    case securityPolicies
    case auditLog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applicationCertificate: return "Application Certificate"
        case .trustedServers: return "Trusted Servers"
        case .rejectedCertificates: return "Rejected Certificates"
        case .userCertificates: return "User Certificates"
        case .securityPolicies: return "Security Policies"
        case .auditLog: return "Audit Log"
        }
    }

    var subtitle: String {
        switch self {
        case .applicationCertificate: return "Instance certificate identity and expiration"
        case .trustedServers: return "Permanent server trust decisions"
        case .rejectedCertificates: return "Blocked or unknown certificates"
        case .userCertificates: return "Client authentication certificates"
        case .securityPolicies: return "Mode and policy posture by profile"
        case .auditLog: return "Certificate and security-sensitive actions"
        }
    }

    var systemImage: String {
        switch self {
        case .applicationCertificate: return "person.badge.key"
        case .trustedServers: return "checkmark.shield"
        case .rejectedCertificates: return "xmark.shield"
        case .userCertificates: return "person.crop.rectangle.badge.checkmark"
        case .securityPolicies: return "lock.doc"
        case .auditLog: return "list.clipboard"
        }
    }

    var tint: Color {
        switch self {
        case .applicationCertificate, .securityPolicies: return .blue
        case .trustedServers: return .green
        case .rejectedCertificates: return .red
        case .userCertificates: return .purple
        case .auditLog: return .orange
        }
    }
}

private struct SecurityHeader: View {
    let connectedServers: Int
    let weakProfiles: [OPCUAServer]

    var body: some View {
        HStack(spacing: 20) {
            SecurityStatusTile(title: "Active Sessions", value: "\(connectedServers)", status: connectedServers > 0 ? "Security visible per session" : "No active sessions", systemImage: "network", tint: .blue)
            SecurityStatusTile(title: "Weak Profiles", value: "\(weakProfiles.count)", status: weakProfiles.isEmpty ? "No weak profile settings" : "Review before production use", systemImage: "exclamationmark.shield", tint: weakProfiles.isEmpty ? .green : .orange)
            SecurityStatusTile(title: "Trust Workflow", value: "Explicit", status: "Fingerprint review required", systemImage: "fingerprint", tint: .green)
        }
        .padding(16)
        .background(.bar)
    }
}

private struct SecurityStatusTile: View {
    let title: String
    let value: String
    let status: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CertificateInventoryView: View {
    let title: String
    let certificates: [CertificateManager.Certificate]
    let emptyMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnterpriseSectionHeader(title: title, subtitle: "Fingerprint, subject, issuer, validity, key usage, and expiration should be reviewed before trust.")

            if certificates.isEmpty {
                ContentUnavailableView(title, systemImage: "lock.shield", description: Text(emptyMessage))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(certificates) {
                    TableColumn("Name") { certificate in
                        Text(certificate.name)
                    }
                    TableColumn("Common Name") { certificate in
                        Text(certificate.commonName)
                    }
                    TableColumn("Fingerprint") { certificate in
                        Text(certificate.thumbprint)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                    }
                    TableColumn("Validity") { certificate in
                        Label(certificate.validityStatus.description, systemImage: certificate.isValid ? "checkmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(certificate.validityStatus.color)
                    }
                    TableColumn("Key") { certificate in
                        Text("\(certificate.keySize) bit \(certificate.signatureAlgorithm)")
                    }
                }
            }
        }
    }
}

private struct SecurityPolicyPostureView: View {
    let servers: [OPCUAServer]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnterpriseSectionHeader(title: "Security Policies", subtitle: "Prefer Sign & Encrypt with Basic256Sha256 or stronger for production profiles.")

            Table(servers) {
                TableColumn("Profile") { server in
                    Text(server.name)
                }
                TableColumn("Endpoint") { server in
                    Text(server.endpoint)
                }
                TableColumn("Mode") { server in
                    Text(server.securityMode.rawValue)
                }
                TableColumn("Policy") { server in
                    Text(server.securityPolicy.displayName)
                }
                TableColumn("Posture") { server in
                    SecurityPostureBadge(server: server)
                }
            }
        }
    }
}

private struct SecurityPostureBadge: View {
    let server: OPCUAServer

    private var label: String {
        if server.securityMode == .none || server.securityPolicy == .none {
            return "Unsecured"
        }
        if server.securityPolicy.isDeprecated {
            return "Deprecated"
        }
        return "Acceptable"
    }

    private var tint: Color {
        switch label {
        case "Acceptable": return .green
        case "Deprecated": return .orange
        default: return .red
        }
    }

    var body: some View {
        Label(label, systemImage: label == "Acceptable" ? "checkmark.circle" : "exclamationmark.triangle")
            .foregroundStyle(tint)
    }
}

private struct SecurityAuditLogView: View {
    @StateObject private var diagnostics = DiagnosticsManager.shared

    private var securityLogs: [LogEntry] {
        diagnostics.logs.filter {
            $0.component.localizedCaseInsensitiveContains("security") ||
            $0.message.localizedCaseInsensitiveContains("certificate") ||
            $0.message.localizedCaseInsensitiveContains("trust")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnterpriseSectionHeader(title: "Audit Log", subtitle: "Security-sensitive actions are surfaced from diagnostics until durable audit persistence is added.")

            Table(securityLogs) {
                TableColumn("Time") { entry in
                    Text(entry.timestamp, style: .time)
                }
                TableColumn("Level") { entry in
                    Text(entry.level.rawValue)
                }
                TableColumn("Component") { entry in
                    Text(entry.component)
                }
                TableColumn("Message") { entry in
                    Text(entry.message)
                }
            }
        }
    }
}

private struct SecurityTablePlaceholder: View {
    let title: String
    let rows: [SecurityTableRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnterpriseSectionHeader(title: title, subtitle: "Trust decisions must be deliberate, visible, and auditable.")
            Table(rows) {
                TableColumn("Field", value: \.field)
                TableColumn("Value", value: \.value)
            }
        }
    }
}

private struct SecurityTableRow: Identifiable {
    let id = UUID()
    let field: String
    let value: String
}
