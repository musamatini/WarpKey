// AppTheme.swift
import Foundation
import SwiftUI

// MARK: - Theme Definition
enum Theme: String, Codable, CaseIterable, Identifiable {
    case greenish = "Greenish"
    case graphite = "Graphite"
    case sunset = "Sunset"
    case ocean = "Ocean"
    case rose = "Rosé"
    case crimson = "Crimson"
    case forest = "Forest"
    case midnight = "Midnight"
    case sapphire = "Sapphire"
    case espresso = "Espresso"
    case orchid = "Orchid"
    case gold = "Gold"
    case mint = "Mint"
    case lavender = "Lavender"
    case slate = "Slate"
    case sky = "Sky"
    case lime = "Lime"
    case tangerine = "Tangerine"
    
    var id: String { self.rawValue }
}

// MARK: - AppTheme
struct AppTheme {
    // MARK: - Layout
    static let cornerRadius: CGFloat = 8

    // MARK: - Dynamic Color Providers
    static func accentColor1(for scheme: ColorScheme, theme: Theme) -> Color {
        // Primary, vibrant action color (buttons, toggles, main highlights)
        switch theme {
        case .greenish: return Color(hex: "B87D4E")
        case .graphite: return scheme == .dark ? Color(hex: "E0E0E0") : Color(hex: "3C3C3F")
        case .sunset:   return Color(hex: "FF9500")
        case .ocean:    return Color(hex: "0A84FF")
        case .rose:     return Color(hex: "D65280")
        case .crimson:  return Color(hex: "FF453A")
        case .forest:   return Color(hex: "30D158")
        case .midnight: return Color(hex: "BF5AF2")
        case .sapphire: return Color(hex: "0F52BA")
        case .espresso: return Color(hex: "5C4033")
        case .orchid:   return Color(hex: "DA70D6")
        case .gold:     return Color(hex: "FFD700")
        case .mint:     return Color(hex: "66CDAA")
        case .lavender: return Color(hex: "967BB6")
        case .slate:    return Color(hex: "708090")
        case .sky:      return Color(hex: "87CEEB")
        case .lime:     return Color(hex: "A7D129")
        case .tangerine:return Color(hex: "F28500")
        }
    }

    static func accentColor2(for scheme: ColorScheme, theme: Theme) -> Color {
        // Secondary, complementary color (icons, selection borders, REC DONE BTN)
        switch theme {
        case .greenish: return Color(hex: "6A9E96")
        case .graphite: return Color(hex: "5856D6")
        case .sunset:   return Color(hex: "BF5AF2")
        case .ocean:    return Color(hex: "64D2FF")
        case .rose:     return Color(hex: "B1B7D1")
        case .crimson:  return Color(hex: "FF8F87")
        case .forest:   return Color(hex: "FFD60A")
        case .midnight: return Color(hex: "64D2FF")
        case .sapphire: return Color(hex: "89CFF0")
        case .espresso: return Color(hex: "D2B48C")
        case .orchid:   return Color(hex: "AFE1AF")
        case .gold:     return Color(hex: "DAA520")
        case .mint:     return Color(hex: "00A99D")
        case .lavender: return Color(hex: "B57EDC")
        case .slate:    return Color(hex: "B0C4DE")
        case .sky:      return Color(hex: "63B4D1")
        case .lime:     return Color(hex: "BEF202")
        case .tangerine:return Color(hex: "F9812A")
        }
    }
    
    static func cardBackgroundColor(for scheme: ColorScheme, theme: Theme) -> Color {
        let darkOpacity = 0.7
        let darkColor: Color
        switch theme {
        case .greenish: darkColor = Color(hex: "1F2D2A").opacity(darkOpacity)
        case .graphite: darkColor = Color(hex: "2C2C2E").opacity(darkOpacity)
        case .sunset:   darkColor = Color(hex: "2E2036").opacity(darkOpacity)
        case .ocean:    darkColor = Color(hex: "1C2A4D").opacity(darkOpacity)
        case .rose:     darkColor = Color(hex: "3F3D4E").opacity(darkOpacity)
        case .crimson:  darkColor = Color(hex: "2B0F0E").opacity(darkOpacity)
        case .forest:   darkColor = Color(hex: "1E3324").opacity(darkOpacity)
        case .midnight: darkColor = Color(hex: "292442").opacity(darkOpacity)
        case .sapphire: darkColor = Color(hex: "0B2545").opacity(darkOpacity)
        case .espresso: darkColor = Color(hex: "211713").opacity(darkOpacity)
        case .orchid:   darkColor = Color(hex: "3D233D").opacity(darkOpacity)
        case .gold:     darkColor = Color(hex: "28241C").opacity(darkOpacity)
        case .mint:     darkColor = Color(hex: "1A3A3A").opacity(darkOpacity)
        case .lavender: darkColor = Color(hex: "322A4A").opacity(darkOpacity)
        case .slate:    darkColor = Color(hex: "2F3437").opacity(darkOpacity)
        case .sky:      darkColor = Color(hex: "2D3B42").opacity(darkOpacity)
        case .lime:     darkColor = Color(hex: "353F0F").opacity(darkOpacity)
        case .tangerine:darkColor = Color(hex: "4B2A00").opacity(darkOpacity)
        }
        return scheme == .dark ? darkColor : Color(hex: "FFFFFF")
    }

    static func pillBackgroundColor(for scheme: ColorScheme, theme: Theme) -> Color {
        let darkOpacity = 0.15
        let darkColor: Color
        switch theme {
        case .greenish: darkColor = Color(hex: "F0F3EF").opacity(darkOpacity)
        case .graphite: darkColor = Color(hex: "E5E5EA").opacity(darkOpacity)
        case .sunset:   darkColor = Color(hex: "F2E6FF").opacity(darkOpacity)
        case .ocean:    darkColor = Color(hex: "DAF2FF").opacity(darkOpacity)
        case .rose:     darkColor = Color(hex: "F2E6FF").opacity(darkOpacity)
        case .crimson:  darkColor = Color(hex: "FFE3E1").opacity(darkOpacity)
        case .forest:   darkColor = Color(hex: "D8F7DF").opacity(darkOpacity)
        case .midnight: darkColor = Color(hex: "EADFFF").opacity(darkOpacity)
        case .sapphire: darkColor = Color(hex: "DAEFFF").opacity(darkOpacity)
        case .espresso: darkColor = Color(hex: "EFEAE4").opacity(darkOpacity)
        case .orchid:   darkColor = Color(hex: "FAE6FA").opacity(darkOpacity)
        case .gold:     darkColor = Color(hex: "FFF8DC").opacity(darkOpacity)
        case .mint:     darkColor = Color(hex: "E0FFF0").opacity(darkOpacity)
        case .lavender: darkColor = Color(hex: "F0E8FF").opacity(darkOpacity)
        case .slate:    darkColor = Color(hex: "E8ECEF").opacity(darkOpacity)
        case .sky:      darkColor = Color(hex: "E7F5FF").opacity(darkOpacity)
        case .lime:     darkColor = Color(hex: "F8FFD7").opacity(darkOpacity)
        case .tangerine:darkColor = Color(hex: "FFEDD6").opacity(darkOpacity)
        }
        let lightColor = Color(hex: "E8E8E8")
        return scheme == .dark ? darkColor : lightColor
    }

    static func pickerBackgroundColor(for scheme: ColorScheme, theme: Theme) -> Color {
        let darkColor = pillBackgroundColor(for: .dark, theme: theme).opacity(0.6)
        let lightColor = pillBackgroundColor(for: .light, theme: theme).opacity(0.7)
        return scheme == .dark ? darkColor : lightColor
    }
    
    static func primaryTextColor(for scheme: ColorScheme) -> Color {
        return scheme == .dark ? Color(hex: "F0F3EF") : Color(hex: "1C1C1E")
    }

    static func secondaryTextColor(for scheme: ColorScheme) -> Color {
        return scheme == .dark ? Color(hex: "F0F3EF").opacity(0.8) : Color(hex: "6D6D72")
    }
    
    static func adaptiveTextColor(on color: Color) -> Color {
        return color.isLight() ? primaryTextColor(for: .light) : .white
    }

    // MARK: - Gradients & Backgrounds
    static func background(for scheme: ColorScheme, theme: Theme) -> some View {
        let darkGradient: Gradient
        switch theme {
        case .greenish: darkGradient = Gradient(colors: [Color(hex: "1F2D2A"), Color(hex: "0D1715")])
        case .graphite: darkGradient = Gradient(colors: [Color(hex: "2C2C2E"), Color(hex: "1C1C1E")])
        case .sunset:   darkGradient = Gradient(colors: [Color(hex: "432B4C"), Color(hex: "1C1220")])
        case .ocean:    darkGradient = Gradient(colors: [Color(hex: "25386A"), Color(hex: "0E162A")])
        case .rose:     darkGradient = Gradient(colors: [Color(hex: "4F4C68"), Color(hex: "292834")])
        case .crimson:  darkGradient = Gradient(colors: [Color(hex: "4B1F1C"), Color(hex: "230E0C")])
        case .forest:   darkGradient = Gradient(colors: [Color(hex: "1A3D21"), Color(hex: "0A180D")])
        case .midnight: darkGradient = Gradient(colors: [Color(hex: "342550"), Color(hex: "130D20")])
        case .sapphire: darkGradient = Gradient(colors: [Color(hex: "0B2545"), Color(hex: "030C18")])
        case .espresso: darkGradient = Gradient(colors: [Color(hex: "211713"), Color(hex: "0D0806")])
        case .orchid:   darkGradient = Gradient(colors: [Color(hex: "3D233D"), Color(hex: "170C17")])
        case .gold:     darkGradient = Gradient(colors: [Color(hex: "3B2F00"), Color(hex: "191400")])
        case .mint:     darkGradient = Gradient(colors: [Color(hex: "1A3A3A"), Color(hex: "0A1A1A")])
        case .lavender: darkGradient = Gradient(colors: [Color(hex: "322A4A"), Color(hex: "14101E")])
        case .slate:    darkGradient = Gradient(colors: [Color(hex: "2F3437"), Color(hex: "121416")])
        case .sky:      darkGradient = Gradient(colors: [Color(hex: "2D3B42"), Color(hex: "11171A")])
        case .lime:     darkGradient = Gradient(colors: [Color(hex: "353F0F"), Color(hex: "141806")])
        case .tangerine:darkGradient = Gradient(colors: [Color(hex: "4B2A00"), Color(hex: "201200")])
        }

        return Group {
            if scheme == .dark {
                RadialGradient(
                    gradient: darkGradient,
                    center: .center,
                    startRadius: 0,
                    endRadius: 1000
                )
            } else {
                RadialGradient(
                    gradient: Gradient(colors: [
                        accentColor1(for: .light, theme: theme).opacity(0.1),
                        Color(hex: "F7F7F7").opacity(0.1)
                    ]),
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 1500
                )
                .overlay(Color(hex: "F6F6F6"))
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
    
    func isLight() -> Bool {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components, components.count >= 3 else {
            return false
        }
        let brightness = (components[0] * 299 + components[1] * 587 + components[2] * 114) / 1000
        return brightness > 0.6
    }
}
