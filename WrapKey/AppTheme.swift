import Foundation
import SwiftUI

// A single source of truth for our app's design system.
struct AppTheme {
    // MARK: - Layout
    static let cornerRadius: CGFloat = 12

    // MARK: - Colors - THEME HUB: "Forest Mist"
    // A natural, calming theme inspired by deep forests and soft mist.

    // --- Core Palette ---
    /// A soft, misty off-white. The primary text color.
    static let mistyWhite = Color(hex: "F0F3EF")
    
    /// A deep, calming muted teal. A strong secondary accent.
    static let mutedTeal = Color(hex: "6A9E96")

    /// A light, gentle sage green. Used for subtle highlights.
    static let lightSage = Color(hex: "A3B8A8")
    
    /// A warm, earthy burnt ochre. The primary pop/accent color.
    static let burntOchre = Color(hex: "B87D4E")
    
    /// A very dark, muted forest green that provides depth and complements the natural palette.
    static let deepForestGreen = Color(hex: "1F2D2A")

    // ✅ NEW COLOR FOR DEEPER GRADIENT POINT
    /// An even deeper, almost black, shade of forest green for the furthest gradient point.
    static let deepestForestGreen = Color(hex: "0D1715") // This is where we get "more green, less black"

    // --- Theme Application ---
    
    // Primary Accent Colors (for elements like buttons or highlights)
    static let accentColor1 = burntOchre      // The ochre is our primary "pop" color
    static let accentColor2 = mutedTeal       // The teal is for secondary actions

    // Structural Colors
    /// Cards use a semi-transparent dark green to float above the background.
    static let cardBackgroundColor = deepForestGreen.opacity(0.7)
    
    /// Pills and inactive elements use a subtle, semi-transparent misty white.
    static let pillBackgroundColor = mistyWhite.opacity(0.15)
    
    /// Picker background uses the same logic.
    static let pickerBackgroundColor = mistyWhite.opacity(0.1)
    
    /// Picker selection uses the stronger muted teal to stand out.
    static let pickerSelectedBackgroundColor = mutedTeal.opacity(0.4)
    
    /// Toggles are tinted with the main accent color for a cohesive feel.
    static let toggleTintColor = burntOchre

    // Text Colors
    /// Primary text is the soft, misty white for excellent contrast on the dark background.
    static let primaryTextColor = mistyWhite
    
    /// Secondary text is slightly transparent for visual hierarchy.
    static let secondaryTextColor = mistyWhite.opacity(0.8)

    // MARK: - Gradients (Convenience)
    
    // ✅ UPDATED DREAMY BACKGROUND - More Pronounced Circle Effect with Mist
    /// A radial gradient that creates a soft vignette, pulling focus to the center.
    /// Now with a subtle misty glow in the center (lightSage) that fades out
    /// to deep forest greens, creating a more noticeable spherical effect.
    static let backgroundGradient = RadialGradient(
        gradient: Gradient(colors: [
            deepForestGreen,         // Transition to the main deep forest green
            deepestForestGreen      // Fade out to the deepest shade
        ]),
        center: .center,
        startRadius: 0,  // Increased radius to make the central "sphere" glow more prominent
        endRadius: 1000   // Large radius for a wide, enveloping gradient
    )
    
    /// The welcome screen uses a more dramatic diagonal linear version for impact.
    static let welcomeGradient = RadialGradient(
        gradient: Gradient(colors: [
            deepForestGreen,         // Transition to the main deep forest green
            deepestForestGreen      // Fade out to the deepest shade
        ]),
        center: .center,
        startRadius: 0,  // Increased radius to make the central "sphere" glow more prominent
        endRadius: 1000   // Large radius for a wide, enveloping gradient
    )
}


// Helper to initialize Color from a Hex string (no changes here)
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
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
