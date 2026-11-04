import SwiftUI

/// Color theme for the device. "Plastic" is the original look.
struct Theme: Equatable {
    var body: Color
    var lcdBackground: Color
    var ink: Color
    var pillKey: Color
    var pillKeyPressed: Color
    var ovalKey: Color
    var ovalKeyPressed: Color
    var keyText: Color
    var noteText: Color
    var convLabel: Color
    var accent: Color
    var accentText: Color
    var colorScheme: ColorScheme

    static let plastic = Theme(
        body: Color(white: 0.13),
        lcdBackground: Color(red: 0.69, green: 0.72, blue: 0.67),
        ink: Color(red: 0.08, green: 0.09, blue: 0.08),
        pillKey: Color(white: 0.30), pillKeyPressed: Color(white: 0.20),
        ovalKey: Color(white: 0.22), ovalKeyPressed: Color(white: 0.30),
        keyText: Color(white: 0.95), noteText: Color(white: 0.62),
        convLabel: Color(white: 0.90),
        accent: Color(red: 1.0, green: 0.68, blue: 0.1), accentText: .black,
        colorScheme: .dark)

    static let night = Theme(
        body: Color(white: 0.04),
        lcdBackground: Color(white: 0.09),
        ink: Color(white: 0.92),
        pillKey: Color(white: 0.17), pillKeyPressed: Color(white: 0.28),
        ovalKey: Color(white: 0.12), ovalKeyPressed: Color(white: 0.24),
        keyText: Color(white: 0.92), noteText: Color(white: 0.55),
        convLabel: Color(white: 0.75),
        accent: Color(red: 1.0, green: 0.68, blue: 0.1), accentText: .black,
        colorScheme: .dark)

    static let light = Theme(
        body: .white,
        lcdBackground: Color(white: 0.95),
        ink: Color(white: 0.08),
        pillKey: Color(white: 0.90), pillKeyPressed: Color(white: 0.78),
        ovalKey: Color(white: 0.94), ovalKeyPressed: Color(white: 0.82),
        keyText: Color(white: 0.10), noteText: Color(white: 0.45),
        convLabel: Color(white: 0.30),
        accent: Color(red: 1.0, green: 0.68, blue: 0.1), accentText: .black,
        colorScheme: .light)

    static let solarizedLight = Theme(
        body: Color(hex: 0xFDF6E3),
        lcdBackground: Color(hex: 0xEEE8D5),
        ink: Color(hex: 0x073642),
        pillKey: Color(hex: 0xE4DDC8), pillKeyPressed: Color(hex: 0xD3CBB5),
        ovalKey: Color(hex: 0xEEE8D5), ovalKeyPressed: Color(hex: 0xDDD6C1),
        keyText: Color(hex: 0x073642), noteText: Color(hex: 0x657B83),
        convLabel: Color(hex: 0x586E75),
        accent: Color(hex: 0xCB4B16), accentText: Color(hex: 0xFDF6E3),
        colorScheme: .light)

    static let pink = Theme(
        body: Color(hex: 0xFCF1F4),
        lcdBackground: Color(hex: 0xF6DEE5),
        ink: Color(hex: 0x3B1F2B),
        pillKey: Color(hex: 0xF0D3DC), pillKeyPressed: Color(hex: 0xE4BFCB),
        ovalKey: Color(hex: 0xF6DEE5), ovalKeyPressed: Color(hex: 0xEACAD4),
        keyText: Color(hex: 0x3B1F2B), noteText: Color(hex: 0x8A6272),
        convLabel: Color(hex: 0x6B4455),
        accent: Color(hex: 0xD6336C), accentText: .white,
        colorScheme: .light)

    static let blue = Theme(
        body: Color(hex: 0xF0F5FB),
        lcdBackground: Color(hex: 0xDFE9F6),
        ink: Color(hex: 0x14263F),
        pillKey: Color(hex: 0xD0DFF1), pillKeyPressed: Color(hex: 0xBBD0E8),
        ovalKey: Color(hex: 0xDFE9F6), ovalKeyPressed: Color(hex: 0xC9DAEE),
        keyText: Color(hex: 0x14263F), noteText: Color(hex: 0x5F7894),
        convLabel: Color(hex: 0x3E5878),
        accent: Color(hex: 0x2F6FD0), accentText: .white,
        colorScheme: .light)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum ThemeChoice: String, CaseIterable, Identifiable {
    case plastic, night, light, system, pink, blue, solarizedLight
    var id: String { rawValue }
    var name: String { self == .solarizedLight ? "Solarized Light" : rawValue.capitalized }
    /// Concrete theme; `.system` follows the device's light/dark setting.
    func resolved(for scheme: ColorScheme) -> Theme {
        self == .system ? (scheme == .dark ? .night : .light) : theme
    }
    var theme: Theme {
        switch self {
        case .plastic: return .plastic
        case .night: return .night
        case .light: return .light
        case .solarizedLight: return .solarizedLight
        case .pink: return .pink
        case .blue: return .blue
        case .system: return .light
        }
    }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = Theme.plastic }

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
