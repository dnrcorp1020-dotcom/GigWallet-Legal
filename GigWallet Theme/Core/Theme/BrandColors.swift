import SwiftUI

enum BrandColors {
    // Primary brand
    static let primary = Color(hex: "FF6B35")
    static let primaryLight = Color(hex: "FF8F66")
    static let primaryDark = Color(hex: "E55A25")

    // Secondary (warm tones to complement brand orange — never navy/blue)
    static let secondary = Color(hex: "8B5E34")
    static let secondaryLight = Color(hex: "A67B52")

    // Semantic
    static let success = Color(hex: "34C759")
    static let warning = Color(hex: "FF9500")
    static let destructive = Color(hex: "FF3B30")
    static let info = Color(hex: "5856D6")

    // Backgrounds
    static let background = Color(uiColor: .systemBackground)
    static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
    static let tertiaryBackground = Color(uiColor: .tertiarySystemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)

    // Text
    static let textPrimary = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let textTertiary = Color(uiColor: .tertiaryLabel)

    // Card
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardShadow = Color.black.opacity(0.08)

    // Platform brand colors
    static let uber = Color(hex: "000000")
    static let lyft = Color(hex: "FF00BF")
    static let doordash = Color(hex: "FF3008")
    static let instacart = Color(hex: "43B02A")
    static let grubhub = Color(hex: "F63440")
    static let ubereats = Color(hex: "06C167")
    static let etsy = Color(hex: "F56400")
    static let airbnb = Color(hex: "FF5A5F")
    static let taskrabbit = Color(hex: "1DBF73")
    static let fiverr = Color(hex: "1DBF73")
    static let upwork = Color(hex: "14A800")
    static let amazonFlex = Color(hex: "FF9900")
    static let shipt = Color(hex: "00A859")
}
