import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme") private var themeName = ThemeChoice.plastic.rawValue

    private let inset: CGFloat = 16
    private let spacing: CGFloat = 16
    private let aspect: CGFloat = 2622.0 / 1206.0

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                // Size thumbnails so two and a half fit in the card, hinting that it scrolls.
                let cardWidth = geo.size.width - inset * 2
                let thumbWidth = (cardWidth - inset - spacing * 2) / 2.5
                VStack(alignment: .leading, spacing: 10) {
                    Text("Theme")
                        .font(.headline)
                        .padding(.horizontal, inset)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: spacing) {
                            ForEach(ThemeChoice.allCases) { choice in
                                thumbnail(choice, width: thumbWidth)
                            }
                        }
                        .padding(.horizontal, inset)
                    }
                    .padding(.vertical, 16)
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, inset)

                    Spacer()
                }
                .padding(.top)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func thumbnail(_ choice: ThemeChoice, width: CGFloat) -> some View {
        let selected = choice.rawValue == themeName
        return Button { themeName = choice.rawValue } label: {
            VStack(spacing: 10) {
                Image("theme_\(choice.rawValue)")
                    .resizable()
                    .frame(width: width, height: width * aspect)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.4),
                                          lineWidth: selected ? 2 : 1)
                    )
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
