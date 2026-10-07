import SwiftUI

enum OrbitSpacing {
    static let small: CGFloat = 4
    static let medium: CGFloat = 10
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 24
    static let minTarget: CGFloat = 44
}

enum OrbitRadius {
    static let card: CGFloat = 16
    static let bubble: CGFloat = 18
    static let chip: CGFloat = 10
}

// Semantic colors follow system appearance, so Dark Mode needs no extra work.
enum OrbitColors {
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let bubbleOwn = Color.accentColor
    static let bubbleOther = Color(uiColor: .secondarySystemBackground)
    static let subtle = Color(uiColor: .secondaryLabel)
    static let danger = Color.red
    static let warning = Color.orange
}
