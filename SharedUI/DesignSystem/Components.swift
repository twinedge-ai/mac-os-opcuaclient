import SwiftUI

struct GlassCard: ViewModifier {
    let cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.3),
                                .white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

struct AnimatedGradientBackground: View {
    @State private var animateGradient = false
    let colors: [Color]
    
    var body: some View {
        LinearGradient(
            colors: colors,
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false
    let color: Color
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 2)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .opacity(isPulsing ? 0 : 0.8)
                    .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: isPulsing)
            )
            .onAppear {
                isPulsing = true
            }
    }
}

struct ModernButton: View {
    let title: String
    let icon: String?
    let style: ButtonStyle
    let action: () -> Void
    
    enum ButtonStyle {
        case primary
        case secondary
        case danger
        case success
        case ghost
    }
    
    init(title: String, icon: String? = nil, style: ButtonStyle = .primary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }
    
    var backgroundColor: Color {
        switch style {
        case .primary: return OPCTheme.Colors.primary
        case .secondary: return OPCTheme.Colors.secondary
        case .danger: return OPCTheme.Colors.error
        case .success: return OPCTheme.Colors.success
        case .ghost: return .clear
        }
    }
    
    var foregroundColor: Color {
        switch style {
        case .ghost: return OPCTheme.Colors.primary
        default: return .white
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: OPCTheme.Spacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(OPCTheme.Typography.callout)
                    .fontWeight(.semibold)
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, OPCTheme.Spacing.lg)
            .padding(.vertical, OPCTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                    .stroke(style == .ghost ? OPCTheme.Colors.border : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(OPCTheme.Animation.fast, value: configuration.isPressed)
    }
}

struct FloatingActionButton: View {
    let icon: String
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(OPCTheme.Colors.Gradient.primary)
                        .shadow(
                            color: OPCTheme.Colors.primary.opacity(0.3),
                            radius: isPressed ? 4 : 8,
                            x: 0,
                            y: isPressed ? 2 : 4
                        )
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity,
                          pressing: { pressing in
            withAnimation(OPCTheme.Animation.fast) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var onCommit: (() -> Void)?
    
    @FocusState private var isFocused: Bool
    @State private var showClearButton = false
    
    var body: some View {
        HStack(spacing: OPCTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(OPCTheme.Colors.secondaryText)
                .font(.system(size: 16))
            
            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .focused($isFocused)
                .onSubmit {
                    onCommit?()
                }
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(OPCTheme.Colors.secondaryText)
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, OPCTheme.Spacing.md)
        .padding(.vertical, OPCTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                .fill(OPCTheme.Colors.secondaryBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                        .stroke(isFocused ? OPCTheme.Colors.primary : OPCTheme.Colors.border, lineWidth: 1)
                )
        )
        .animation(OPCTheme.Animation.fast, value: isFocused)
        .animation(OPCTheme.Animation.fast, value: text.isEmpty)
    }
}

struct StatusBadge: View {
    let status: ConnectionStatus
    let showPulse: Bool
    
    init(status: ConnectionStatus, showPulse: Bool = true) {
        self.status = status
        self.showPulse = showPulse
    }
    
    var body: some View {
        HStack(spacing: OPCTheme.Spacing.xs) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
                .if(status == .connected && showPulse) { view in
                    view.modifier(PulseAnimation(color: status.color))
                }
            
            Text(status.rawValue)
                .font(OPCTheme.Typography.caption1)
                .fontWeight(.medium)
                .foregroundColor(status.color)
        }
        .padding(.horizontal, OPCTheme.Spacing.sm)
        .padding(.vertical, OPCTheme.Spacing.xs)
        .background(
            Capsule()
                .fill(status.color.opacity(0.1))
        )
    }
}

struct ModernMetricCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let icon: String
    let trend: Trend?
    
    enum Trend {
        case up(Double)
        case down(Double)
        case neutral
        
        var color: Color {
            switch self {
            case .up: return OPCTheme.Colors.success
            case .down: return OPCTheme.Colors.error
            case .neutral: return OPCTheme.Colors.secondaryText
            }
        }
        
        var icon: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .neutral: return "minus"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPCTheme.Spacing.md) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(OPCTheme.Colors.primary)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(OPCTheme.Colors.primary.opacity(0.1))
                    )
                
                Spacer()
                
                if let trend = trend {
                    HStack(spacing: OPCTheme.Spacing.xs) {
                        Image(systemName: trend.icon)
                            .font(.system(size: 12, weight: .bold))
                        if case let .up(value) = trend {
                            Text("+\(value, specifier: "%.1f")%")
                                .font(OPCTheme.Typography.caption1)
                                .fontWeight(.semibold)
                        } else if case let .down(value) = trend {
                            Text("-\(value, specifier: "%.1f")%")
                                .font(OPCTheme.Typography.caption1)
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(trend.color)
                }
            }
            
            VStack(alignment: .leading, spacing: OPCTheme.Spacing.xs) {
                Text(value)
                    .font(OPCTheme.Typography.title1)
                    .fontWeight(.bold)
                    .foregroundColor(OPCTheme.Colors.text)
                
                Text(title)
                    .font(OPCTheme.Typography.subheadline)
                    .foregroundColor(OPCTheme.Colors.secondaryText)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(OPCTheme.Typography.caption1)
                        .foregroundColor(OPCTheme.Colors.tertiaryText)
                }
            }
        }
        .padding(OPCTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassCard(cornerRadius: OPCTheme.Radius.lg))
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}