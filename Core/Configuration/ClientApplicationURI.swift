import Foundation

/// Default OPC UA `applicationURI` for new server profiles. A stable per-install
/// UUID is generated once and persisted in UserDefaults so identical builds
/// across machines don't share an identifier that servers can use to fingerprint
/// or bind certificates to. The user can still override it per-profile.
enum ClientApplicationURI {
    private static let userDefaultsKey = "opcua.client.applicationURI"

    static var installDefault: String {
        if let existing = UserDefaults.standard.string(forKey: userDefaultsKey),
           !existing.isEmpty {
            return existing
        }
        let generated = "urn:opcua-client:macos:\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(generated, forKey: userDefaultsKey)
        return generated
    }
}
