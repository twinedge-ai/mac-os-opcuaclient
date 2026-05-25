import Foundation

struct ConnectionErrorDetail: Equatable {
    let message: String
    let hints: [String]
    let actions: [ConnectionRecoveryAction]

    var formattedMessage: String {
        guard !hints.isEmpty else { return message }
        let hintText = hints.map { "• \($0)" }.joined(separator: "\n")
        return "\(message)\n\nTry:\n\(hintText)"
    }
}

enum ConnectionRecoveryAction: String {
    case editServer
    case retryConnection

    var title: String {
        switch self {
        case .editServer:
            return "Edit Settings"
        case .retryConnection:
            return "Retry"
        }
    }
}
