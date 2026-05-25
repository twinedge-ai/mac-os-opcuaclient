import Foundation
import SwiftUI
import Combine

class CertificateManager: ObservableObject {
    static let shared = CertificateManager()

    @Published var userCertificates: [Certificate] = []
    @Published var trustedCertificates: [Certificate] = []

    struct Certificate: Identifiable, Codable {
        var id: UUID = UUID()
        var name: String
        var commonName: String
        var organization: String?
        var country: String?
        var validFrom: Date
        var validUntil: Date
        var thumbprint: String
        var isTrusted: Bool = false
        var keySize: Int = 2048
        var signatureAlgorithm: String = "SHA256"

        var isValid: Bool {
            Date() >= validFrom && Date() <= validUntil
        }

        var validityStatus: ValidityStatus {
            let now = Date()
            if now < validFrom {
                return .notYetValid
            } else if now > validUntil {
                return .expired
            } else {
                let daysUntilExpiry = Calendar.current.dateComponents([.day], from: now, to: validUntil).day ?? 0
                if daysUntilExpiry <= 30 {
                    return .expiringSoon(days: daysUntilExpiry)
                }
                return .valid
            }
        }

        enum ValidityStatus {
            case valid
            case expired
            case notYetValid
            case expiringSoon(days: Int)

            var color: Color {
                switch self {
                case .valid: return .green
                case .expired, .notYetValid: return .red
                case .expiringSoon: return .orange
                }
            }

            var description: String {
                switch self {
                case .valid: return "Valid"
                case .expired: return "Expired"
                case .notYetValid: return "Not Yet Valid"
                case .expiringSoon(let days): return "Expires in \(days) days"
                }
            }
        }
    }

    private init() {}
}
