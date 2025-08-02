//AppTheme.swift
import Foundation
import SwiftUI



struct AppTheme {
    // MARK: - Core Palette
    private static let mistyWhite = Color(hex: "F0F3EF")
    private static let mutedTeal = Color(hex: "6A9E96")
    private static let lightSage = Color(hex: "A3B8A8")
    private static let burntOchre = Color(hex: "B87D4E")
    private static let deepForestGreen = Color(hex: "1F2D2A")
    private static let deepestForestGreen = Color(hex: "0D1715")
    
    private static let lightBackground = Color(hex: "F6F6F6")
    private static let lightCardBackground = Color.white
    private static let lightPillBackground = Color(hex: "E8E8E8")
    private static let lightPrimaryText = Color(hex: "1C1C1E")
    private static let lightSecondaryText = Color(hex: "6D6D72")

    // MARK: - Layout
    static let cornerRadius: CGFloat = 10

    // MARK: - Dynamic Theme Application
    static func accentColor1(for scheme: ColorScheme) -> Color {
        return burntOchre
    }
    
    static func accentColor2(for scheme: ColorScheme) -> Color {
        return mutedTeal
    }
    
    static func cardBackgroundColor(for scheme: ColorScheme) -> Color {
        return scheme == .dark ? deepForestGreen.opacity(0.7) : lightCardBackground
    }
    
    static func pillBackgroundColor(for scheme: ColorScheme) -> Color {
        return scheme == .dark ? mistyWhite.opacity(0.15) : lightPillBackground
    }
    
    static func pickerBackgroundColor(for scheme: ColorScheme) -> Color {
        return scheme == .dark ? mistyWhite.opacity(0.1) : lightPillBackground.opacity(0.7)
    }
    
    static func pickerSelectedBackgroundColor(for scheme: ColorScheme) -> Color {
        return scheme == .dark ? mutedTeal.opacity(0.4) : mutedTeal.opacity(0.7)
    }
    
    static func toggleTintColor(for scheme: ColorScheme) -> Color {
        return burntOchre
    }
    
    static func primaryTextColor(for scheme: ColorScheme) -> Color {
        return scheme == .dark ? mistyWhite : lightPrimaryText
    }
    
    static func secondaryTextColor(for scheme: ColorScheme) -> Color {
        return scheme == .dark ? mistyWhite.opacity(0.8) : lightSecondaryText
    }

    // MARK: - Gradients & Backgrounds
    static func background(for scheme: ColorScheme) -> some View {
        Group {
            if scheme == .dark {
                RadialGradient(
                    gradient: Gradient(colors: [deepForestGreen, deepestForestGreen]),
                    center: .center,
                    startRadius: 0,
                    endRadius: 1000
                )
            } else {
                lightBackground
            }
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
