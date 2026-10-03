import SwiftUI

/// Creazione di una nota: mostra tutte le configurazioni di carta disponibili.
struct NewNoteSheet: View {
    var onCreate: (String, PaperStyle) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.defaultPaper) private var lastStyleRaw = PaperStyle.pageLined.rawValue
    @State private var title = ""
    @State private var style: PaperStyle = .pageLined
    @FocusState private var titleFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 22, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    TextField("Titolo della nota", text: $title)
                        .font(.serif(.largeTitle, weight: .bold))
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .onSubmit(create)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline))

                    section(
                        title: "Fogli infiniti",
                        subtitle: "Un foglio enorme che cresce mentre scrivi",
                        styles: PaperStyle.infiniteStyles
                    )
                    section(
                        title: "Fogli normali",
                        subtitle: "Pagine in formato A4, aggiungine quante vuoi",
                        styles: PaperStyle.pageStyles
                    )
                }
                .padding(28)
            }
            .background(Theme.background)
            .navigationTitle("Nuova nota")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea", action: create)
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .onAppear {
            style = PaperStyle(rawValue: lastStyleRaw) ?? .pageLined
        }
    }

    private func section(title: String, subtitle: String, styles: [PaperStyle]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.serif(.title2, weight: .semibold))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(styles) { option in
                    PaperOptionCard(style: option, isSelected: option == style)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) { style = option }
                        }
                }
            }
        }
    }

    private func create() {
        lastStyleRaw = style.rawValue
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty
            ? "Nota del " + Date().formatted(.dateTime.day().month(.wide))
            : trimmed
        dismiss()
        onCreate(finalTitle, style)
    }
}

private struct PaperOptionCard: View {
    let style: PaperStyle
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PaperPreview(style: style)
                .aspectRatio(0.74, contentMode: .fit)
                .overlay {
                    if style.isInfinite {
                        // Bordi sfumati: suggeriscono che il foglio continua.
                        LinearGradient(colors: [.clear, .white.opacity(0.0), Theme.background.opacity(0.55)], startPoint: .center, endPoint: .bottomTrailing)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? Theme.accent : Color.black.opacity(0.08), lineWidth: isSelected ? 3 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    if style.isInfinite {
                        Image(systemName: "infinity")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(7)
                            .glassEffect(.regular, in: .capsule)
                            .padding(8)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Theme.accent)
                            .padding(10)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .shadow(color: .black.opacity(isSelected ? 0.16 : 0.08), radius: isSelected ? 14 : 8, y: isSelected ? 8 : 4)
                .scaleEffect(isSelected ? 1.03 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(style.title).font(.serif(.headline, weight: .semibold))
                Text(style.subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
