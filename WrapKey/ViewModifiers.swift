import SwiftUI

// The ViewModifier that contains the background logic
struct FrostedGlassBackground: ViewModifier {
    var blurMaterial: Material
    var tintColor: Color
    var tintOpacity: Double

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Layer 1: The blur material itself.
                    Rectangle()
                        .foregroundStyle(blurMaterial)

                    // Layer 2: A tint color layered on top with adjustable opacity.
                    // To make the blur BRIGHTER, use .white with a low opacity.
                    // To make it DARKER, use .black with a low opacity.
                    Rectangle()
                        .fill(tintColor.opacity(tintOpacity))
                }
            )
    }
}

// An extension to make the modifier easy to use
extension View {
    func frostedGlass(
        blurMaterial: Material = .regularMaterial,
        tintColor: Color = .white,
        tintOpacity: Double = 0.15
    ) -> some View {
        self.modifier(
            FrostedGlassBackground(
                blurMaterial: blurMaterial,
                tintColor: tintColor,
                tintOpacity: tintOpacity
            )
        )
    }
}
