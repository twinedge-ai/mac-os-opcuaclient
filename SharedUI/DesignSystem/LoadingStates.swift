import SwiftUI

// MARK: - Loading State Management

/// A comprehensive loading state system for consistent UX across the application
enum LoadingState: Equatable {
    case idle
    case loading
    case success
    case error(String)
    
    var isLoading: Bool {
        switch self {
        case .loading: return true
        default: return false
        }
    }
    
    var isSuccess: Bool {
        switch self {
        case .success: return true
        default: return false
        }
    }
    
    var isError: Bool {
        switch self {
        case .error: return true
        default: return false
        }
    }
    
    var errorMessage: String? {
        switch self {
        case .error(let message): return message
        default: return nil
        }
    }
}

// MARK: - Loading UI Components

/// A modern loading overlay with customizable content
struct ModernLoadingOverlay: View {
    let title: String
    let subtitle: String?
    let progress: Double?
    let showCancel: Bool
    let onCancel: (() -> Void)?
    
    init(
        title: String,
        subtitle: String? = nil,
        progress: Double? = nil,
        showCancel: Bool = false,
        onCancel: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.showCancel = showCancel
        self.onCancel = onCancel
    }
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .transition(.opacity)
            
            // Loading card
            VStack(spacing: DesignSystem.Spacing.large) {
                // Animation
                ZStack {
                    // Pulsing circles
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(DesignSystem.Colors.primary.opacity(0.3), lineWidth: 2)
                            .frame(width: 60 + CGFloat(index * 20))
                            .scaleEffect(1 + sin(Date().timeIntervalSince1970 + Double(index) * 0.5) * 0.1)
                            .animation(
                                .easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                                value: Date().timeIntervalSince1970
                            )
                    }
                    
                    // Center icon
                    Image(systemName: "network")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.primary)
                }
                .frame(height: 100)
                
                // Content
                VStack(spacing: DesignSystem.Spacing.small) {
                    Text(title)
                        .font(DesignSystem.Typography.headline)
                        .multilineTextAlignment(.center)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                }
                
                // Progress indicator
                if let progress = progress {
                    VStack(spacing: DesignSystem.Spacing.xSmall) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                            .tint(DesignSystem.Colors.primary)
                        
                        Text("\(Int(progress * 100))%")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundColor(DesignSystem.Colors.tertiaryText)
                    }
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(DesignSystem.Colors.primary)
                }
                
                // Cancel button
                if showCancel {
                    Button("Cancel", action: onCancel ?? {})
                        .buttonStyle(.bordered)
                }
            }
            .padding(DesignSystem.Spacing.xxLarge)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .fill(DesignSystem.Colors.background)
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .transition(.scale.combined(with: .opacity))
        }
        .allowsHitTesting(true)
    }
}

/// Skeleton loading placeholder for content areas
struct SkeletonView: View {
    let lines: Int
    let animated: Bool
    
    @State private var animationOffset: CGFloat = -1
    
    init(lines: Int = 3, animated: Bool = true) {
        self.lines = lines
        self.animated = animated
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            ForEach(0..<lines, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(skeletonColor)
                    .frame(height: 16)
                    .frame(maxWidth: index == lines - 1 ? .infinity * 0.7 : .infinity)
                    .overlay(
                        animated ? animationOverlay : nil
                    )
            }
        }
        .onAppear {
            if animated {
                startAnimation()
            }
        }
    }
    
    private var skeletonColor: Color {
        DesignSystem.Colors.tertiaryBackground
    }
    
    private var animationOverlay: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(
                LinearGradient(
                    colors: [
                        Color.clear,
                        DesignSystem.Colors.background.opacity(0.6),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .offset(x: animationOffset * 400) // Fixed width for animation
    }
    
    private func startAnimation() {
        withAnimation(
            .linear(duration: 1.5)
            .repeatForever(autoreverses: false)
        ) {
            animationOffset = 1
        }
    }
}

/// Loading state wrapper for any view
struct LoadingStateView<Content: View, LoadingView: View, ErrorView: View>: View {
    let state: LoadingState
    let content: () -> Content
    let loadingView: () -> LoadingView
    let errorView: (String) -> ErrorView
    let retryAction: (() -> Void)?
    
    init(
        state: LoadingState,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder loadingView: @escaping () -> LoadingView = { SkeletonView() },
        @ViewBuilder errorView: @escaping (String) -> ErrorView = { ErrorStateView(message: $0) },
        retryAction: (() -> Void)? = nil
    ) {
        self.state = state
        self.content = content
        self.loadingView = loadingView
        self.errorView = errorView
        self.retryAction = retryAction
    }
    
    var body: some View {
        Group {
            switch state {
            case .idle, .success:
                content()
            case .loading:
                loadingView()
            case .error(let message):
                errorView(message)
            }
        }
    }
}

/// Error state view with retry capability
struct ErrorStateView: View {
    let message: String
    let retryAction: (() -> Void)?
    
    init(message: String, retryAction: (() -> Void)? = nil) {
        self.message = message
        self.retryAction = retryAction
    }
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(DesignSystem.Colors.error)
            
            VStack(spacing: DesignSystem.Spacing.small) {
                Text("Something went wrong")
                    .font(DesignSystem.Typography.headline)
                
                Text(message)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            
            if let retryAction = retryAction {
                Button("Try Again", action: retryAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.large)
    }
}

/// Inline loading indicator for smaller UI elements
struct InlineLoadingIndicator: View {
    let size: Size
    let color: Color
    
    enum Size {
        case small, medium, large
        
        var value: CGFloat {
            switch self {
            case .small: return 16
            case .medium: return 24
            case .large: return 32
            }
        }
    }
    
    init(size: Size = .medium, color: Color = DesignSystem.Colors.primary) {
        self.size = size
        self.color = color
    }
    
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .scaleEffect(size.value / 24) // Scale based on default size of 24
            .tint(color)
    }
}

/// Loading button that shows loading state
struct LoadingButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void
    
    init(_ title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.xSmall) {
                if isLoading {
                    InlineLoadingIndicator(size: .small, color: .white)
                }
                
                Text(isLoading ? "Loading..." : title)
                    .font(DesignSystem.Typography.callout.weight(.medium))
            }
        }
        .disabled(isLoading)
        .buttonStyle(.borderedProminent)
    }
}

/// Progress card for multi-step operations
struct ProgressCard: View {
    let title: String
    let currentStep: Int
    let totalSteps: Int
    let stepDescription: String
    let progress: Double
    let onCancel: (() -> Void)?
    
    var body: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                        Text(title)
                            .font(DesignSystem.Typography.headline)
                        
                        Text("Step \(currentStep) of \(totalSteps)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                    
                    Spacer()
                    
                    if let onCancel = onCancel {
                        Button("Cancel", action: onCancel)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                
                // Progress bar
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(DesignSystem.Colors.primary)
                    
                    HStack {
                        Text(stepDescription)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                        
                        Spacer()
                        
                        Text("\(Int(progress * 100))%")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.primary)
                            .fontWeight(.medium)
                    }
                }
            }
        }
    }
}

// MARK: - Loading State Modifiers

extension View {
    /// Adds a loading overlay to any view
    func loadingOverlay(
        _ isLoading: Bool,
        title: String = "Loading...",
        subtitle: String? = nil
    ) -> some View {
        ZStack {
            self
                .disabled(isLoading)
            
            if isLoading {
                ModernLoadingOverlay(title: title, subtitle: subtitle)
            }
        }
    }
    
    /// Wraps view in loading state management
    func loadingState<LoadingView: View, ErrorView: View>(
        _ state: LoadingState,
        @ViewBuilder loadingView: @escaping () -> LoadingView = { SkeletonView() },
        @ViewBuilder errorView: @escaping (String) -> ErrorView = { ErrorStateView(message: $0) },
        retryAction: (() -> Void)? = nil
    ) -> some View {
        LoadingStateView(
            state: state,
            content: { self },
            loadingView: loadingView,
            errorView: errorView,
            retryAction: retryAction
        )
    }
}

// MARK: - Specific Loading Scenarios

/// Loading states for specific OPC UA operations
enum OPCUALoadingState {
    case connecting(serverName: String)
    case browsing(nodePath: String)
    case subscribing(itemCount: Int)
    case testing(endpoint: String)
    
    var title: String {
        switch self {
        case .connecting: return "Connecting to Server"
        case .browsing: return "Browsing Address Space"
        case .subscribing: return "Creating Subscription"
        case .testing: return "Testing Connection"
        }
    }
    
    var subtitle: String {
        switch self {
        case .connecting(let serverName):
            return "Establishing connection to \(serverName)..."
        case .browsing(let nodePath):
            return "Loading nodes from \(nodePath)..."
        case .subscribing(let itemCount):
            return "Setting up monitoring for \(itemCount) items..."
        case .testing(let endpoint):
            return "Verifying connection to \(endpoint)..."
        }
    }
}

/// OPC UA specific loading overlay
struct OPCUALoadingOverlay: View {
    let loadingState: OPCUALoadingState
    let progress: Double?
    let onCancel: (() -> Void)?
    
    var body: some View {
        ModernLoadingOverlay(
            title: loadingState.title,
            subtitle: loadingState.subtitle,
            progress: progress,
            showCancel: onCancel != nil,
            onCancel: onCancel
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        SkeletonView(lines: 3)
        
        LoadingButton("Test Connection", isLoading: true) {}
        
        ProgressCard(
            title: "Connecting to Server",
            currentStep: 2,
            totalSteps: 4,
            stepDescription: "Establishing secure connection...",
            progress: 0.5,
            onCancel: {}
        )
    }
    .padding()
}