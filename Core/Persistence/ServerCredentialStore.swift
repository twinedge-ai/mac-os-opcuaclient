import Foundation
import Security

enum ServerCredentialStore {
    nonisolated private static var service: String {
        "twinedgeai.com.MacOpcUaClient.server-passwords"
    }

    nonisolated static func password(for serverId: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverId.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    nonisolated static func savePassword(_ password: String?, for serverId: UUID) -> Bool {
        guard let password, !password.isEmpty else {
            return deletePassword(for: serverId)
        }

        let encodedPassword = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverId.uuidString
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: encodedPassword,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus != errSecItemNotFound {
            print("Failed to update server password in Keychain: \(updateStatus)")
            return false
        }

        var addQuery = query
        addQuery.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            print("Failed to save server password in Keychain: \(addStatus)")
            return false
        }

        return true
    }

    @discardableResult
    nonisolated static func deletePassword(for serverId: UUID) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverId.uuidString
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return true
        }

        print("Failed to delete server password from Keychain: \(status)")
        return false
    }
}

enum ServerSecurityFileRole: String, CaseIterable {
    case clientCertificate
    case privateKey
    case serverCertificate
}

enum ServerSecurityFileStore {
    nonisolated private static var service: String {
        "twinedgeai.com.MacOpcUaClient.server-security-files"
    }

    nonisolated private struct StoredFile: Codable {
        let path: String
        let bookmarkData: Data?
    }

    nonisolated static func path(for serverId: UUID, role: ServerSecurityFileRole) -> String? {
        storedFile(for: serverId, role: role)?.path
    }

    @discardableResult
    nonisolated static func savePath(_ path: String?, for serverId: UUID, role: ServerSecurityFileRole) -> Bool {
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return deletePath(for: serverId, role: role)
        }

        let expandedPath = (path as NSString).expandingTildeInPath
        let storedFile = StoredFile(
            path: expandedPath,
            bookmarkData: makeSecurityScopedBookmark(for: URL(fileURLWithPath: expandedPath))
        )

        guard let data = try? JSONEncoder().encode(storedFile) else {
            print("Failed to encode security file reference for \(role.rawValue)")
            return false
        }

        let query: [String: Any] = baseQuery(serverId: serverId, role: role)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus != errSecItemNotFound {
            print("Failed to update security file reference in Keychain: \(updateStatus)")
            return false
        }

        var addQuery = query
        addQuery.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            print("Failed to save security file reference in Keychain: \(addStatus)")
            return false
        }

        return true
    }

    @discardableResult
    nonisolated static func deletePath(for serverId: UUID, role: ServerSecurityFileRole) -> Bool {
        let status = SecItemDelete(baseQuery(serverId: serverId, role: role) as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return true
        }

        print("Failed to delete security file reference from Keychain: \(status)")
        return false
    }

    @discardableResult
    nonisolated static func deleteAll(for serverId: UUID) -> Bool {
        ServerSecurityFileRole.allCases
            .map { deletePath(for: serverId, role: $0) }
            .allSatisfy { $0 }
    }

    nonisolated static func withAccess<T>(
        serverId: UUID,
        role: ServerSecurityFileRole,
        fallbackPath: String,
        _ body: (String) -> T
    ) -> T {
        let fallbackURL = URL(fileURLWithPath: (fallbackPath as NSString).expandingTildeInPath)
        let url = resolvedURL(for: serverId, role: role) ?? fallbackURL

        #if os(macOS)
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        #endif

        return body(url.path)
    }

    nonisolated private static func baseQuery(serverId: UUID, role: ServerSecurityFileRole) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(serverId.uuidString).\(role.rawValue)"
        ]
    }

    nonisolated private static func storedFile(for serverId: UUID, role: ServerSecurityFileRole) -> StoredFile? {
        var query = baseQuery(serverId: serverId, role: role)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let storedFile = try? JSONDecoder().decode(StoredFile.self, from: data) else {
            return nil
        }

        return storedFile
    }

    nonisolated private static func resolvedURL(for serverId: UUID, role: ServerSecurityFileRole) -> URL? {
        guard let storedFile = storedFile(for: serverId, role: role) else {
            return nil
        }

        #if os(macOS)
        if let bookmarkData = storedFile.bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale {
                    _ = savePath(url.path, for: serverId, role: role)
                }
                return url
            }
        }
        #endif

        return URL(fileURLWithPath: storedFile.path)
    }

    nonisolated private static func makeSecurityScopedBookmark(for url: URL) -> Data? {
        #if os(macOS)
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        return nil
        #endif
    }
}
