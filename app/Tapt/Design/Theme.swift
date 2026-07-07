import SwiftUI

/// Tapt brand tokens - "Elevated Taproom". See docs/06-BRAND.md.
enum Brand {
    // Core palette
    static let malt   = Color(hex: 0x1A1206)
    static let foam   = Color(hex: 0xFBF6EC)
    static let gold   = Color(hex: 0xF2A900)   // the one signature accent
    static let hop    = Color(hex: 0x3F8F5B)   // No/Low + success
    static let copper = Color(hex: 0xB4531F)
    static let haze   = Color(hex: 0xEFE7D6)
    static let ink    = Color(hex: 0x6B5E49)

    // Semantic, theme-aware
    static let accent     = gold
    static let background = Color(light: 0xFBF6EC, dark: 0x140E05)
    static let surface    = Color(light: 0xFFFCF4, dark: 0x20160B)
    static let text       = Color(light: 0x1A1206, dark: 0xFBF6EC)
    static let muted      = Color(light: 0x6E6046, dark: 0xB7A88B)
}

extension Color {
    init(hex: UInt) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8)  & 0xFF) / 255.0,
                  blue:  Double( hex        & 0xFF) / 255.0)
    }
    /// Dynamic light/dark color.
    init(light: UInt, dark: UInt) {
        self = Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}
