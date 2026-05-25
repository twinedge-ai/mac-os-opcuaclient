import SwiftUI

// MARK: - Modern Design System for OPC UA Client

/// A comprehensive design system for consistent, modern UI across the application
struct DesignSystem {
    
    // MARK: - Colors
    struct Colors {
        // Primary brand colors
        static let primary = Color.blue
        static let primaryGradient = LinearGradient(
            colors: [Color.blue, Color.blue.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        // Semantic colors
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue
        
        // Background colors
        static let background = Color.windowBackgroundColor
        static let secondaryBackground = Color.controlBackgroundColor
        static let tertiaryBackground = Color.gray.opacity(0.05)
        static let cardBackground = Color.controlBackgroundColor
        
        // Text colors
        static let primaryText = Color.primary
        static let secondaryText = Color.secondary
        static let tertiaryText = Color.gray
        
        // Border colors
        static let borderLight = Color.gray.opacity(0.2)
        static let borderMedium = Color.gray.opacity(0.3)
        static let borderStrong = Color.gray.opacity(0.5)
    }
    
    // MARK: - Typography
    struct Typography {
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .default)
        static let title = Font.system(size: 28, weight: .bold, design: .default)
        static let title2 = Font.system(size: 22, weight: .semibold, design: .default)
        static let title3 = Font.system(size: 20, weight: .semibold, design: .default)
        static let headline = Font.system(size: 17, weight: .semibold, design: .default)
        static let body = Font.system(size: 15, weight: .regular, design: .default)
        static let callout = Font.system(size: 14, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 13, weight: .regular, design: .default)
        static let footnote = Font.system(size: 12, weight: .regular, design: .default)
        static let caption = Font.system(size: 11, weight: .regular, design: .default)
        static let caption2 = Font.system(size: 10, weight: .regular, design: .default)
        
        // Special styles
        static let monospacedBody = Font.system(size: 14, design: .monospaced)
        static let monospacedCaption = Font.system(size: 12, design: .monospaced)
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xxxSmall: CGFloat = 2
        static let xxSmall: CGFloat = 4
        static let xSmall: CGFloat = 8
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let xLarge: CGFloat = 24
        static let xxLarge: CGFloat = 32
        static let xxxLarge: CGFloat = 40
    }
    
    // MARK: - Corner Radius
    struct CornerRadius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
        static let xLarge: CGFloat = 20
    }
    
    // MARK: - Shadows
    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
    
    struct Shadows {
        static let small = ShadowStyle(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        static let medium = ShadowStyle(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        static let large = ShadowStyle(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
        static let card = ShadowStyle(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 2)
    }
    
    // MARK: - Animation
    struct Animation {
        static let fast = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let normal = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.5)
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.8)
    }
}

// MARK: - Reusable UI Components

/// Modern styled card container
struct ModernCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = DesignSystem.Spacing.medium
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(DesignSystem.Colors.cardBackground)
            .cornerRadius(DesignSystem.CornerRadius.medium)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

/// Modern section header
struct SectionHeader: View {
    let title: String
    let icon: String?
    
    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xSmall) {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(DesignSystem.Colors.primary)
                    .font(.system(size: 16, weight: .semibold))
            }
            Text(title)
                .font(DesignSystem.Typography.headline)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.vertical, DesignSystem.Spacing.xSmall)
    }
}

/// Modern text field with consistent styling
struct ModernTextField: View {
    let title: String
    @Binding var text: String
    var icon: String? = nil
    var placeholder: String? = nil
    var isSecure: Bool = false
    // keyboardType is iOS-specific, not available on macOS
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
            // Label
            HStack(spacing: DesignSystem.Spacing.xxSmall) {
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundColor(DesignSystem.Colors.primary)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .textCase(.uppercase)
            }
            
            // Text field
            Group {
                if isSecure {
                    SecureField(placeholder ?? title, text: $text)
                } else {
                    TextField(placeholder ?? title, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .padding(DesignSystem.Spacing.small)
            .background(Color.gray.opacity(0.06))
            .cornerRadius(DesignSystem.CornerRadius.small)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .stroke(DesignSystem.Colors.borderLight, lineWidth: 1)
            )
        }
    }
}

/// Modern picker with consistent styling
struct ModernPicker<SelectionValue: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    let content: Content
    var icon: String? = nil
    
    init(
        _ title: String,
        selection: Binding<SelectionValue>,
        icon: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._selection = selection
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
            // Label
            HStack(spacing: DesignSystem.Spacing.xxSmall) {
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundColor(DesignSystem.Colors.primary)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .textCase(.uppercase)
            }
            
            // Picker
            Picker("", selection: $selection) {
                content
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.xSmall)
            .padding(.horizontal, DesignSystem.Spacing.small)
            .background(Color.gray.opacity(0.06))
            .cornerRadius(DesignSystem.CornerRadius.small)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .stroke(DesignSystem.Colors.borderLight, lineWidth: 1)
            )
        }
    }
}

/// Modern button styles
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.callout.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.large)
            .padding(.vertical, DesignSystem.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(isEnabled ? DesignSystem.Colors.primary : Color.gray)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(DesignSystem.Animation.fast, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.callout.weight(.medium))
            .foregroundColor(isEnabled ? DesignSystem.Colors.primary : Color.gray)
            .padding(.horizontal, DesignSystem.Spacing.large)
            .padding(.vertical, DesignSystem.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .stroke(isEnabled ? DesignSystem.Colors.primary : Color.gray, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(DesignSystem.Animation.fast, value: configuration.isPressed)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.callout.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.large)
            .padding(.vertical, DesignSystem.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(DesignSystem.Colors.error)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(DesignSystem.Animation.fast, value: configuration.isPressed)
    }
}

/// Info/Help tooltip component
struct InfoTooltip: View {
    let text: String
    @State private var showingTooltip = false
    
    var body: some View {
        Button(action: { showingTooltip.toggle() }) {
            Image(systemName: "questionmark.circle")
                .foregroundColor(DesignSystem.Colors.info)
                .font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingTooltip) {
            Text(text)
                .font(DesignSystem.Typography.caption)
                .padding(DesignSystem.Spacing.small)
                .frame(maxWidth: 250)
        }
    }
}

// StatusBadge is already defined in Components.swift

/// Empty state view for design system
struct DesignSystemEmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(DesignSystem.Colors.tertiaryText)
            
            VStack(spacing: DesignSystem.Spacing.xSmall) {
                Text(title)
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(.primary)
                
                Text(message)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            
            if let action = action, let label = actionLabel {
                Button(action: action) {
                    Label(label, systemImage: "plus.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.xxxLarge)
    }
}

// MARK: - Form Components

/// Modern form container
struct ModernForm<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                content
            }
            .padding(DesignSystem.Spacing.large)
        }
        .background(DesignSystem.Colors.background)
    }
}

/// Form section with modern styling
struct FormSection<Content: View>: View {
    let title: String?
    let content: Content
    
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            if let title = title {
                Text(title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(.primary)
                    .padding(.bottom, DesignSystem.Spacing.xxSmall)
            }
            
            VStack(spacing: DesignSystem.Spacing.medium) {
                content
            }
            .padding(DesignSystem.Spacing.medium)
            .background(DesignSystem.Colors.secondaryBackground)
            .cornerRadius(DesignSystem.CornerRadius.medium)
        }
    }
}

// MARK: - Dialog Components

/// Modern dialog/sheet header
struct DialogHeader: View {
    let title: String
    let subtitle: String?
    let icon: String?
    let onDismiss: () -> Void
    
    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: DesignSystem.Spacing.small) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.primary)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(DesignSystem.Typography.title3)
                            .foregroundColor(.primary)
                        
                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                        }
                    }
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(DesignSystem.Colors.tertiaryText)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
            }
            .padding(DesignSystem.Spacing.large)
            
            Divider()
        }
        .background(DesignSystem.Colors.background)
    }
}

/// Dialog footer with action buttons
struct DialogFooter: View {
    let primaryAction: () -> Void
    let primaryLabel: String
    let cancelAction: () -> Void
    var isDestructive: Bool = false
    var isPrimaryDisabled: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: DesignSystem.Spacing.small) {
                Button("Cancel", action: cancelAction)
                    .buttonStyle(SecondaryButtonStyle())
                
                Spacer()
                
                if isDestructive {
                    Button(primaryLabel, action: primaryAction)
                        .buttonStyle(DestructiveButtonStyle())
                        .disabled(isPrimaryDisabled)
                } else {
                    Button(primaryLabel, action: primaryAction)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isPrimaryDisabled)
                }
            }
            .padding(DesignSystem.Spacing.large)
        }
        .background(DesignSystem.Colors.background)
    }
}

// MARK: - Extensions

extension View {
    /// Apply modern card styling
    func modernCard(padding: CGFloat = DesignSystem.Spacing.medium) -> some View {
        self
            .padding(padding)
            .background(DesignSystem.Colors.cardBackground)
            .cornerRadius(DesignSystem.CornerRadius.medium)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    /// Apply standard dialog size
    func dialogSize() -> some View {
        self
            .frame(minWidth: 500, idealWidth: 600, maxWidth: 800)
            .frame(minHeight: 400, idealHeight: 500, maxHeight: 700)
    }
}