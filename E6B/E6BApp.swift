import SwiftUI

@main
struct E6BApp: App {
    var body: some Scene {
        WindowGroup { ThemedRoot() }
    }
}

/// Resolves the chosen theme (following the system appearance for "System")
/// and injects it into the view tree.
private struct ThemedRoot: View {
    @AppStorage("theme") private var themeName = ThemeChoice.plastic.rawValue
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let choice = ThemeChoice(rawValue: themeName) ?? .plastic
        let theme = choice.resolved(for: systemScheme)
        ContentView()
            .environment(\.theme, theme)
            .preferredColorScheme(choice == .system ? nil : theme.colorScheme)
    }
}
