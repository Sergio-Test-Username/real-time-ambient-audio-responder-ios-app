import SwiftUI

enum Theme {
    static let accent = Color(red: 0.54, green: 0.66, blue: 1.0)
    static let accent2 = Color(red: 0.36, green: 0.30, blue: 1.0)
    static let bgTop = Color(red: 0.04, green: 0.05, blue: 0.13)
    static let bgBottom = Color(red: 0.10, green: 0.07, blue: 0.24)
    static let card = Color.white.opacity(0.07)
    static let cardStroke = Color.white.opacity(0.10)
    static let textSecondary = Color.white.opacity(0.6)

    static var background: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View {
        modifier(CardStyle())
    }
}

extension SceneKind {
    var color: Color {
        switch self {
        case .silence: return Color(red: 0.50, green: 0.55, blue: 0.80)
        case .speech: return Color(red: 0.98, green: 0.74, blue: 0.30)
        case .music: return Color(red: 0.55, green: 0.45, blue: 1.0)
        case .dj: return Color(red: 1.0, green: 0.35, blue: 0.65)
        case .birds: return Color(red: 0.35, green: 0.85, blue: 0.55)
        case .wind: return Color(red: 0.55, green: 0.85, blue: 0.95)
        case .water: return Color(red: 0.25, green: 0.65, blue: 1.0)
        case .crowd: return Color(red: 1.0, green: 0.55, blue: 0.35)
        case .ambient: return Color(red: 0.60, green: 0.80, blue: 1.0)
        }
    }
}
