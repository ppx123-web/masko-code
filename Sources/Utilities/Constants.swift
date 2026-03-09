import SwiftUI

enum Constants {
    // Web links (opened in browser)
    #if DEBUG
    static let maskoBaseURL = "http://localhost:3000"
    #else
    static let maskoBaseURL = "https://masko.ai"
    #endif

    // Local hook server
    static let defaultServerHost: String = "0.0.0.0"
    static var serverHost: String {
        guard let stored = UserDefaults.standard.string(forKey: "serverHost"), !stored.isEmpty else {
            return defaultServerHost
        }
        return stored
    }
    static func setServerHost(_ host: String) {
        UserDefaults.standard.set(host, forKey: "serverHost")
    }

    static let defaultServerPort: UInt16 = 49152
    static var serverPort: UInt16 {
        let stored = UserDefaults.standard.integer(forKey: "serverPort")
        return stored > 0 ? UInt16(stored) : defaultServerPort
    }
    static func setServerPort(_ port: UInt16) {
        UserDefaults.standard.set(Int(port), forKey: "serverPort")
    }

    // Brand colors — matches masko.ai web design
    static let orangePrimary = Color(red: 249/255, green: 93/255, blue: 2/255)     // #f95d02
    static let orangeHover = Color(red: 251/255, green: 121/255, blue: 16/255)     // #fb7910
    static let orangeShadow = Color(red: 201/255, green: 74/255, blue: 1/255)      // #c94a01
    static let textPrimary = Color(red: 35/255, green: 17/255, blue: 60/255)       // #23113c
    static let textMuted = Color(red: 35/255, green: 17/255, blue: 60/255).opacity(0.65)
    static let lightBackground = Color(red: 250/255, green: 249/255, blue: 247/255) // #faf9f7
    static let surfaceWhite = Color.white
    static let border = Color(red: 35/255, green: 17/255, blue: 60/255).opacity(0.12)
    static let borderHover = Color(red: 35/255, green: 17/255, blue: 60/255).opacity(0.20)

    // Interactive state colors (matches website sidebar)
    static let chip = Color(red: 231/255, green: 173/255, blue: 104/255).opacity(0.18)       // warm hover bg
    static let stage = Color(red: 35/255, green: 17/255, blue: 60/255).opacity(0.04)          // subtle hover
    static let orangePrimaryLight = Color(red: 249/255, green: 93/255, blue: 2/255).opacity(0.10)  // active item bg
    static let orangePrimarySubtle = Color(red: 249/255, green: 93/255, blue: 2/255).opacity(0.08) // selected row bg

    // MARK: - Typography

    /// Fredoka — headings, buttons, display text
    static func heading(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom("Fredoka", size: size).weight(weight)
    }

    /// Rubik — body text, labels, metadata
    static func body(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Rubik", size: size).weight(weight)
    }

    // MARK: - Layout

    static let cornerRadius: CGFloat = 14
    static let cornerRadiusSmall: CGFloat = 10

    // MARK: - Shadows

    /// Default card shadow
    static let cardShadowColor = Color(red: 35/255, green: 17/255, blue: 60/255).opacity(0.08)
    static let cardShadowRadius: CGFloat = 1.5
    static let cardShadowY: CGFloat = 1

    /// Hover card shadow
    static let cardHoverShadowColor = Color(red: 35/255, green: 17/255, blue: 60/255).opacity(0.12)
    static let cardHoverShadowRadius: CGFloat = 6
    static let cardHoverShadowY: CGFloat = 4

    // MARK: - Gradients

    /// Feature card orange tint gradient (matches web)
    static let featureCardGradient = LinearGradient(
        colors: [
            Color(red: 249/255, green: 93/255, blue: 2/255).opacity(0.06),
            Color(red: 252/255, green: 155/255, blue: 43/255).opacity(0.06)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
