import SwiftUI

public struct SimpleOPCTheme {
    public struct Colors {
        public static let primary = Color.blue
        public static let secondary = Color.green
        public static let accent = Color.purple
        public static let success = Color.green
        public static let warning = Color.orange
        public static let error = Color.red
        public static let info = Color.blue
        
        public static let background = Color.windowBackgroundColor
        public static let secondaryBackground = Color.controlBackgroundColor
        public static let tertiaryBackground = Color.tertiaryLabelColor.opacity(0.1)
        
        public static let text = Color.primary
        public static let secondaryText = Color.secondary
        public static let tertiaryText = Color.tertiaryLabelColor
        
        public static let divider = Color.separatorColor
        public static let border = Color.separatorColor
    }
    
    public struct Typography {
        public static let largeTitle = Font.largeTitle
        public static let title1 = Font.title
        public static let title2 = Font.title2
        public static let title3 = Font.title3
        public static let headline = Font.headline
        public static let body = Font.body
        public static let callout = Font.callout
        public static let subheadline = Font.subheadline
        public static let footnote = Font.footnote
        public static let caption1 = Font.caption
        public static let caption2 = Font.caption2
        
        public static let monospacedBody = Font.system(.body, design: .monospaced)
        public static let monospacedSmall = Font.system(.caption, design: .monospaced)
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
}