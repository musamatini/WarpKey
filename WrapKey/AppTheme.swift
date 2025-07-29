//AppTheme.swift
import Foundation
import SwiftUI

// MARK: - App Design System
struct AppTheme {
    // MARK: - Layout
    static let cornerRadius: CGFloat = 12

    // MARK: - Colors - "Forest Mist"
    static let mistyWhite = Color(hex: "F0F3EF")
    static let mutedTeal = Color(hex: "6A9E96")
    static let lightSage = Color(hex: "A3B8A8")
    static let burntOchre = Color(hex: "B87D4E")
    static let deepForestGreen = Color(hex: "1F2D2A")
    static let deepestForestGreen = Color(hex: "0D1715")

    // MARK: - Theme Application
    static let accentColor1 = burntOchre
    static let accentColor2 = mutedTeal
    static let cardBackgroundColor = deepForestGreen.opacity(0.7)
    static let pillBackgroundColor = mistyWhite.opacity(0.15)
    static let pickerBackgroundColor = mistyWhite.opacity(0.1)
    static let pickerSelectedBackgroundColor = mutedTeal.opacity(0.4)
    static let toggleTintColor = burntOchre
    static let primaryTextColor = mistyWhite
    static let secondaryTextColor = mistyWhite.opacity(0.8)

    // MARK: - Gradients
    static let backgroundGradient = RadialGradient(
        gradient: Gradient(colors: [deepForestGreen, deepestForestGreen]),
        center: .center,
        startRadius: 0,
        endRadius: 1000
    )
    static let welcomeGradient = RadialGradient(
        gradient: Gradient(colors: [deepForestGreen, deepestForestGreen]),
        center: .center,
        startRadius: 0,
        endRadius: 1000
    )
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
