import SwiftUI

enum Typography {
    // Display
    static let largeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let title = Font.system(.title2, design: .rounded, weight: .semibold)
    static let title3 = Font.system(.title3, design: .rounded, weight: .semibold)

    // Body
    static let headline = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.system(.body, design: .default)
    static let bodyMedium = Font.system(.body, design: .default, weight: .medium)
    static let callout = Font.system(.callout, design: .default)
    static let subheadline = Font.system(.subheadline, design: .default)
    static let footnote = Font.system(.footnote, design: .default)
    static let caption = Font.system(.caption, design: .default, weight: .medium)
    static let caption2 = Font.system(.caption2, design: .default)

    // Money display — Dynamic Type responsive
    // Uses system text styles so fonts scale with user's accessibility settings
    static let moneyHero = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let moneyLarge = Font.system(.title, design: .rounded, weight: .bold)
    static let moneyMedium = Font.system(.title2, design: .rounded, weight: .semibold)
    static let moneySmall = Font.system(.title3, design: .rounded, weight: .medium)
    static let moneyCaption = Font.system(.headline, design: .rounded, weight: .medium)
}
