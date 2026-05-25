import SwiftUI

struct OPCUAStatusCode: Hashable, Codable {
    let rawValue: UInt32
    let symbol: String
    let description: String
    let remediation: String

    static let good = OPCUAStatusCode(
        rawValue: 0x00000000,
        symbol: "Good",
        description: "The operation completed successfully.",
        remediation: "No action required."
    )

    static let uncertain = OPCUAStatusCode(
        rawValue: 0x40000000,
        symbol: "Uncertain",
        description: "The server returned a value whose quality cannot be guaranteed.",
        remediation: "Check source timestamp, server health, and the node quality chain."
    )

    static let bad = OPCUAStatusCode(
        rawValue: 0x80000000,
        symbol: "Bad",
        description: "The operation failed.",
        remediation: "Inspect diagnostics for endpoint, service call, and request context."
    )

    var severity: Severity {
        if rawValue & 0x80000000 == 0x80000000 {
            return .bad
        }
        if rawValue & 0x40000000 == 0x40000000 {
            return .uncertain
        }
        return .good
    }

    static func decode(_ rawValue: UInt32) -> OPCUAStatusCode {
        if let known = knownCodes[rawValue] {
            return known
        }

        return OPCUAStatusCode(
            rawValue: rawValue,
            symbol: String(format: "0x%08X", rawValue),
            description: defaultDescription(for: rawValue),
            remediation: defaultRemediation(for: rawValue)
        )
    }

    private static let knownCodes: [UInt32: OPCUAStatusCode] = [
        0x00000000: .good,
        0x40000000: .uncertain,
        0x80000000: .bad,
        0x80050000: OPCUAStatusCode(rawValue: 0x80050000, symbol: "BadTimeout", description: "The operation timed out.", remediation: "Check endpoint reachability, server load, and requested timeout."),
        0x801F0000: OPCUAStatusCode(rawValue: 0x801F0000, symbol: "BadUserAccessDenied", description: "The user does not have permission for the operation.", remediation: "Check authentication mode, role permissions, and node access level."),
        0x80340000: OPCUAStatusCode(rawValue: 0x80340000, symbol: "BadNodeIdUnknown", description: "The server does not recognize the requested NodeId.", remediation: "Refresh namespaces, verify namespace URI/index mapping, and rebrowse the node."),
        0x80740000: OPCUAStatusCode(rawValue: 0x80740000, symbol: "BadNotWritable", description: "The target attribute or variable is not writable.", remediation: "Check AccessLevel/UserAccessLevel before writing."),
        0x80750000: OPCUAStatusCode(rawValue: 0x80750000, symbol: "BadOutOfRange", description: "The value is outside the server's accepted range.", remediation: "Inspect engineering range, data type, and server-side validation constraints."),
        0x80850000: OPCUAStatusCode(rawValue: 0x80850000, symbol: "BadCertificateUntrusted", description: "The certificate is not trusted.", remediation: "Review fingerprint, issuer, validity, and trust decision before retrying.")
    ]

    private static func defaultDescription(for rawValue: UInt32) -> String {
        switch OPCUAStatusCode(rawValue: rawValue, symbol: "", description: "", remediation: "").severity {
        case .good: return "The server reported good quality."
        case .uncertain: return "The server reported uncertain quality."
        case .bad: return "The server reported a bad status."
        }
    }

    private static func defaultRemediation(for rawValue: UInt32) -> String {
        switch OPCUAStatusCode(rawValue: rawValue, symbol: "", description: "", remediation: "").severity {
        case .good: return "No action required."
        case .uncertain: return "Inspect timestamps, data source health, and diagnostics."
        case .bad: return "Decode the service response and inspect diagnostics for request context."
        }
    }

    enum Severity: String, Codable {
        case good = "Good"
        case uncertain = "Uncertain"
        case bad = "Bad"

        var color: Color {
            switch self {
            case .good: return .green
            case .uncertain: return .orange
            case .bad: return .red
            }
        }

        var systemImage: String {
            switch self {
            case .good: return "checkmark.circle"
            case .uncertain: return "questionmark.circle"
            case .bad: return "xmark.octagon"
            }
        }
    }
}
