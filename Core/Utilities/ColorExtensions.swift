import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension Color {
    static var secondarySystemBackground: Color {
        #if os(iOS)
        return Color(UIColor.secondarySystemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    
    static var secondarySystemGroupedBackground: Color {
        #if os(iOS)
        return Color(UIColor.secondarySystemGroupedBackground)
        #else
        return Color(NSColor.controlBackgroundColor).opacity(0.95)
        #endif
    }
    
    static var tertiarySystemGroupedBackground: Color {
        #if os(iOS)
        return Color(UIColor.tertiarySystemGroupedBackground)
        #else
        return Color(NSColor.controlBackgroundColor).opacity(0.9)
        #endif
    }

    static var windowBackgroundColor: Color {
        #if os(iOS)
        return Color(UIColor.systemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }

    static var controlBackgroundColor: Color {
        #if os(iOS)
        return Color(UIColor.secondarySystemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }

    static var tertiaryLabelColor: Color {
        #if os(iOS)
        return Color(UIColor.tertiaryLabel)
        #else
        return Color(NSColor.tertiaryLabelColor)
        #endif
    }

    static var separatorColor: Color {
        #if os(iOS)
        return Color(UIColor.separator)
        #else
        return Color(NSColor.separatorColor)
        #endif
    }
}