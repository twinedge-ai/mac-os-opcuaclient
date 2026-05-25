import SwiftUI

public struct OPCTheme {
    
    public struct Colors {
        public static let primary = Color("BrandPrimary", bundle: .main)
        public static let primaryDark = Color("PrimaryDarkColor", bundle: .main)
        public static let secondary = Color("OPCSecondaryColor", bundle: .main)
        public static let accent = Color("AccentColor", bundle: .main)
        public static let success = Color(hex: "10B981")
        public static let warning = Color(hex: "F59E0B")
        public static let error = Color(hex: "EF4444")
        public static let info = Color(hex: "3B82F6")
        
        public static let background = Color("BackgroundColor", bundle: .main)
        public static let secondaryBackground = Color("SecondaryBackgroundColor", bundle: .main)
        public static let tertiaryBackground = Color("TertiaryBackgroundColor", bundle: .main)
        
        public static let text = Color("TextColor", bundle: .main)
        public static let secondaryText = Color("SecondaryTextColor", bundle: .main)
        public static let tertiaryText = Color("TertiaryTextColor", bundle: .main)
        
        public static let divider = Color("DividerColor", bundle: .main)
        public static let border = Color("BorderColor", bundle: .main)
        
        public struct Gradient {
            public static let primary = LinearGradient(
                colors: [Color(hex: "6366F1"), Color(hex: "8B5CF6")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            public static let secondary = LinearGradient(
                colors: [Color(hex: "EC4899"), Color(hex: "F43F5E")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            public static let success = LinearGradient(
                colors: [Color(hex: "10B981"), Color(hex: "34D399")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    public struct Typography {
        public static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
        public static let title1 = Font.system(size: 28, weight: .semibold, design: .rounded)
        public static let title2 = Font.system(size: 22, weight: .semibold, design: .rounded)
        public static let title3 = Font.system(size: 20, weight: .semibold, design: .rounded)
        public static let headline = Font.system(size: 17, weight: .semibold, design: .default)
        public static let body = Font.system(size: 17, weight: .regular, design: .default)
        public static let callout = Font.system(size: 16, weight: .regular, design: .default)
        public static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
        public static let footnote = Font.system(size: 13, weight: .regular, design: .default)
        public static let caption1 = Font.system(size: 12, weight: .regular, design: .default)
        public static let caption2 = Font.system(size: 11, weight: .regular, design: .default)
        
        public static let monospacedBody = Font.system(size: 15, design: .monospaced)
        public static let monospacedSmall = Font.system(size: 13, design: .monospaced)
    }
    
    public struct Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let xxxl: CGFloat = 48
    }
    
    public struct Radius {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 6
        public static let md: CGFloat = 8
        public static let lg: CGFloat = 12
        public static let xl: CGFloat = 16
        public static let xxl: CGFloat = 24
        public static let round: CGFloat = 999
    }
    
    public struct Shadow {
        public static let sm = ShadowStyle(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        public static let md = ShadowStyle(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        public static let lg = ShadowStyle(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        public static let xl = ShadowStyle(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
        
        public struct ShadowStyle {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
    }
    
    public struct Animation {
        public static let fast = SwiftUI.Animation.easeInOut(duration: 0.15)
        public static let normal = SwiftUI.Animation.easeInOut(duration: 0.25)
        public static let slow = SwiftUI.Animation.easeInOut(duration: 0.35)
        public static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
        public static let bouncy = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.5)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct ThemeModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(nil)
    }
}

extension View {
    func themed() -> some View {
        self.modifier(ThemeModifier())
    }
}
