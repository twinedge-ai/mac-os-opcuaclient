import SwiftUI
import Combine

// MARK: - Error Types

/// Comprehensive error system for OPC UA operations
protocol AppError: Error, LocalizedError {
    var title: String { get }
    var message: String { get }
    var suggestions: [String] { get }
    var severity: ErrorSeverity { get }
    var category: ErrorCategory { get }
    var canRetry: Bool { get }
    var technicalDetails: String? { get }
}

enum ErrorSeverity {
    case info
    case warning
    case error
    case critical
    
    var color: Color {
        switch self {
        case .info: return DesignSystem.Colors.info
        case .warning: return DesignSystem.Colors.warning
        case .error: return DesignSystem.Colors.error
        case .critical: return Color.red
        }
    }
    
    var icon: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .critical: return "exclamationmark.octagon"
        }
    }
}

enum ErrorCategory {
    case network
    case authentication
    case configuration
    case validation
    case system
    case userInput
    
    var displayName: String {
        switch self {
        case .network: return "Network"
        case .authentication: return "Authentication"
        case .configuration: return "Configuration"
        case .validation: return "Validation"
        case .system: return "System"
        case .userInput: return "User Input"
        }
    }
}

// MARK: - Specific Error Types

struct OPCUAConnectionError: AppError {
    let endpoint: String
    let underlyingError: Error?
    
    var title: String { "Connection Failed" }
    
    var message: String {
        "Unable to connect to OPC UA server at \(endpoint)"
    }
    
    var suggestions: [String] {
        [
            "Verify the server is running and accessible",
            "Check that the endpoint URL is correct",
            "Ensure firewall settings allow OPC UA traffic",
            "Verify security settings match server configuration"
        ]
    }
    
    var severity: ErrorSeverity { .error }
    var category: ErrorCategory { .network }
    var canRetry: Bool { true }
    
    var technicalDetails: String? {
        underlyingError?.localizedDescription
    }
    
    var errorDescription: String? { message }
}

struct AuthenticationError: AppError {
    let username: String?
    
    var title: String { "Authentication Failed" }
    
    var message: String {
        if let username = username {
            return "Authentication failed for user '\(username)'"
        } else {
            return "Authentication failed"
        }
    }
    
    var suggestions: [String] {
        [
            "Check username and password are correct",
            "Verify the user account exists on the server",
            "Ensure the user has sufficient permissions",
            "Try authenticating with a different account"
        ]
    }
    
    var severity: ErrorSeverity { .warning }
    var category: ErrorCategory { .authentication }
    var canRetry: Bool { true }
    var technicalDetails: String? { nil }
    
    var errorDescription: String? { message }
}

struct ValidationError: AppError {
    let field: String
    let value: String
    let requirement: String
    
    var title: String { "Validation Error" }
    
    var message: String {
        "Invalid value for \(field): \(requirement)"
    }
    
    var suggestions: [String] {
        [
            "Check the \(field) value meets requirements",
            "Refer to the help text for correct format",
            "Try using a different value"
        ]
    }
    
    var severity: ErrorSeverity { .warning }
    var category: ErrorCategory { .validation }
    var canRetry: Bool { false }
    var technicalDetails: String? { "Value: '\(value)'" }
    
    var errorDescription: String? { message }
}

struct NodeAccessError: AppError {
    let nodeId: String
    let operation: String
    
    var title: String { "Node Access Error" }
    
    var message: String {
        "Cannot \(operation) node '\(nodeId)'"
    }
    
    var suggestions: [String] {
        [
            "Verify the node exists on the server",
            "Check access permissions for the node",
            "Ensure the server supports this operation",
            "Try refreshing the address space"
        ]
    }
    
    var severity: ErrorSeverity { .error }
    var category: ErrorCategory { .configuration }
    var canRetry: Bool { true }
    var technicalDetails: String? { "Node ID: \(nodeId), Operation: \(operation)" }
    
    var errorDescription: String? { message }
}

struct CertificateError: AppError {
    let id = "certificate_error"
    let path: String
    let reason: String
    
    var title: String { "Certificate Error" }
    
    var message: String {
        "Certificate issue: \(reason)"
    }
    
    var suggestions: [String] {
        [
            "Verify the certificate file exists at the specified path",
            "Check the certificate is valid and not expired",
            "Ensure the certificate format is supported",
            "Try generating a new certificate"
        ]
    }
    
    var severity: ErrorSeverity { .error }
    var category: ErrorCategory { .configuration }
    var canRetry: Bool { false }
    
    var technicalDetails: String? { "Path: \(path)" }
    
    var errorDescription: String? { message }
}

// MARK: - Error Manager

@MainActor
class ErrorManager: ObservableObject {
    @Published var currentError: (any AppError)?
    @Published var errorHistory: [(any AppError)] = []
    @Published var showingErrorDetail = false
    
    static let shared = ErrorManager()
    
    private init() {}
    
    func handle(_ error: any AppError) {
        currentError = error
        errorHistory.insert(error, at: 0)
        
        // Keep only recent errors
        if errorHistory.count > 50 {
            errorHistory.removeLast()
        }
        
        // Log error for debugging
        logError(error)
    }
    
    func handle(_ error: Error) {
        if let appError = error as? any AppError {
            handle(appError)
        } else {
            // Convert generic error to AppError
            let genericError = GenericError(underlyingError: error)
            handle(genericError)
        }
    }
    
    func clearCurrentError() {
        currentError = nil
    }
    
    func showErrorDetail() {
        showingErrorDetail = true
    }
    
    private func logError(_ error: any AppError) {
        print("🔴 ERROR [\(error.category.displayName)]: \(error.message)")
        if let technical = error.technicalDetails {
            print("   Technical: \(technical)")
        }
        print("   Suggestions: \(error.suggestions.joined(separator: ", "))")
    }
}

struct GenericError: AppError {
    let id = UUID().uuidString
    let underlyingError: Error
    
    var title: String { "An Error Occurred" }
    
    var message: String {
        underlyingError.localizedDescription
    }
    
    var suggestions: [String] {
        [
            "Try the operation again",
            "Check your network connection",
            "Contact support if the problem persists"
        ]
    }
    
    var severity: ErrorSeverity { .error }
    var category: ErrorCategory { .system }
    var canRetry: Bool { true }
    
    var technicalDetails: String? {
        "\(underlyingError)"
    }
    
    var errorDescription: String? { message }
}

// MARK: - Error UI Components

/// Modern error banner for inline display
struct ErrorBanner: View {
    let error: any AppError
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main banner content
            HStack(spacing: DesignSystem.Spacing.medium) {
                // Error icon
                Image(systemName: error.severity.icon)
                    .foregroundColor(error.severity.color)
                    .font(.system(size: 20, weight: .medium))
                
                // Error content
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                    Text(error.title)
                        .font(DesignSystem.Typography.callout.weight(.medium))
                    
                    Text(error.message)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
                
                Spacer()
                
                // Actions
                HStack(spacing: DesignSystem.Spacing.xSmall) {
                    if error.canRetry, let onRetry = onRetry {
                        Button("Retry") {
                            onRetry()
                            onDismiss()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    if !error.suggestions.isEmpty {
                        Button(action: { withAnimation { isExpanded.toggle() } }) {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DesignSystem.Spacing.medium)
            .background(error.severity.color.opacity(0.1))
            .overlay(
                Rectangle()
                    .fill(error.severity.color)
                    .frame(width: 4),
                alignment: .leading
            )
            
            // Expanded suggestions
            if isExpanded && !error.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                    Text("SUGGESTIONS")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(DesignSystem.Colors.tertiaryText)
                    
                    ForEach(Array(error.suggestions.enumerated()), id: \.offset) { index, suggestion in
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.xSmall) {
                            Text("\(index + 1).")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.tertiaryText)
                            
                            Text(suggestion)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.medium)
                .background(DesignSystem.Colors.tertiaryBackground)
            }
        }
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .shadow(radius: 2)
    }
}

/// Error detail sheet
struct ErrorDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    let error: any AppError
    let onRetry: (() -> Void)?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                    // Header
                    HStack {
                        Image(systemName: error.severity.icon)
                            .foregroundColor(error.severity.color)
                            .font(.title)
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                            Text(error.title)
                                .font(DesignSystem.Typography.title2)
                                .fontWeight(.semibold)
                            
                            Text(error.category.displayName)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                        }
                        
                        Spacer()
                    }
                    
                    // Message
                    ModernCard {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                            SectionHeader("DESCRIPTION", icon: "text.alignleft")
                            
                            Text(error.message)
                                .font(DesignSystem.Typography.body)
                        }
                    }
                    
                    // Suggestions
                    if !error.suggestions.isEmpty {
                        ModernCard {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                                SectionHeader("SUGGESTIONS", icon: "lightbulb")
                                
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                                    ForEach(Array(error.suggestions.enumerated()), id: \.offset) { index, suggestion in
                                        HStack(alignment: .top, spacing: DesignSystem.Spacing.xSmall) {
                                            Circle()
                                                .fill(DesignSystem.Colors.primary)
                                                .frame(width: 6, height: 6)
                                                .padding(.top, 6)
                                            
                                            Text(suggestion)
                                                .font(DesignSystem.Typography.callout)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Technical Details
                    if let technicalDetails = error.technicalDetails {
                        ModernCard {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                                SectionHeader("TECHNICAL DETAILS", icon: "gear")
                                
                                Text(technicalDetails)
                                    .font(DesignSystem.Typography.monospacedCaption)
                                    .padding(DesignSystem.Spacing.small)
                                    .background(DesignSystem.Colors.tertiaryBackground)
                                    .cornerRadius(DesignSystem.CornerRadius.small)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    
                    // Actions
                    if error.canRetry, let onRetry = onRetry {
                        Button(action: {
                            onRetry()
                            dismiss()
                        }) {
                            Label("Try Again", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .padding()
            }
            .navigationTitle("Error Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }
}

/// Toast notification for quick error display
struct ErrorToast: View {
    let error: any AppError
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Image(systemName: error.severity.icon)
                .foregroundColor(error.severity.color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title)
                    .font(DesignSystem.Typography.caption.weight(.medium))
                    .lineLimit(1)
                
                Text(error.message)
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(DesignSystem.Colors.tertiaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(DesignSystem.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.background)
                .shadow(radius: 8)
        )
        .scaleEffect(isVisible ? 1 : 0.8)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring()) {
                isVisible = true
            }
            
            // Auto dismiss after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation(.spring()) {
                    isVisible = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss()
                }
            }
        }
    }
}

// MARK: - Error Handling Modifiers

extension View {
    /// Adds error handling capability to any view
    func errorHandling() -> some View {
        self.overlay(
            ErrorHandlingOverlay()
        )
    }
    
    /// Shows error banner for specific error
    func errorBanner(
        error: (any AppError)?,
        onDismiss: @escaping () -> Void,
        onRetry: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 0) {
            if let error = error {
                ErrorBanner(error: error, onDismiss: onDismiss, onRetry: onRetry)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            self
        }
    }
}

struct ErrorHandlingOverlay: View {
    @EnvironmentObject var errorManager: ErrorManager
    
    var body: some View {
        ZStack {
            if let error = errorManager.currentError {
                VStack {
                    ErrorToast(error: error) {
                        errorManager.clearCurrentError()
                    }
                    .padding()
                    
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $errorManager.showingErrorDetail) {
            if let error = errorManager.currentError {
                ErrorDetailSheet(error: error, onRetry: nil)
            }
        }
    }
}

// MARK: - Result Extensions

extension Result {
    /// Converts Result to LoadingState for UI binding
    func toLoadingState() -> LoadingState {
        switch self {
        case .success:
            return .success
        case .failure(let error):
            if let appError = error as? any AppError {
                return .error(appError.message)
            } else {
                return .error(error.localizedDescription)
            }
        }
    }
}

#Preview {
    let sampleError = OPCUAConnectionError(
        endpoint: "opc.tcp://localhost:4840",
        underlyingError: nil
    )
    
    VStack(spacing: 20) {
        ErrorBanner(error: sampleError, onDismiss: {}, onRetry: {})
        
        ErrorToast(error: sampleError, onDismiss: {})
    }
    .padding()
}