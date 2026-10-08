import SwiftData
import SwiftUI

/// Scelta di icona (e colore, per le cartelle).
struct CustomizeSheet: View {
    let title: LocalizedStringKey
    @Binding var iconName: String?
    var colorName: Binding<String>?
    var previewName: String
    var previewDocumentCount = 2

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var tint: Color {
        if let colorName { return (FolderColor(rawValue: colorName.wrappedValue) ?? .terracotta).color }
        return Theme.accent
    }

    private var filteredCategories: [IconCategory] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return IconLibrary.categories }
        return IconLibrary.categories.compactMap { category in
            if category.name.lowercased().contains(query) { return category }
            let icons = category.icons.filter { $0.replacingOccurrences(of: ".", with: " ").contains(query) }
            return icons.isEmpty ? nil : IconCategory(name: category.name, icons: icons)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    preview
                        .frame(maxWidth: .infinity)

                    if let colorName {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Colore")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 14)], spacing: 14) {
                                ForEach(FolderColor.allCases) { color in
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                                            colorName.wrappedValue = color.rawValue
                                        }
                                    } label: {
                                        Circle()
                                            .fill(color.color.gradient)
                                            .frame(width: 42, height: 42)
                                            .overlay {
                                                if colorName.wrappedValue == color.rawValue {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 16, weight: .bold))
                                                        .foregroundStyle(.white)
                                                        .transition(.scale)
                                                }
                                            }
                                            .padding(3)
                                            .overlay(Circle().strokeBorder(colorName.wrappedValue == color.rawValue ? color.color : .clear, lineWidth: 2))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(color.displayName)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SectionHeader(title: "Icona")
                            if iconName != nil {
                                Button("Rimuovi icona", role: .destructive) {
                                    withAnimation { iconName = nil }
                                }
                                .font(.subheadline)
                            }
                        }
                        Text(colorName == nil ? "Facoltativa: comparirà sopra la nota." : "Facoltativa: comparirà sopra la cartella.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    InlineSearchField(text: $search, prompt: "Cerca icone o materie", width: nil, drawsBackground: true)

                    if filteredCategories.isEmpty {
                        Text("Nessuna icona trovata per “\(search)”.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(filteredCategories) { category in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category.name)
                                .font(.serif(.headline, weight: .semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 12)], spacing: 12) {
                                ForEach(category.icons, id: \.self) { icon in
                                    let selected = iconName == icon
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { iconName = icon }
                                    } label: {
                                        Image(systemName: icon)
                                            .font(.system(size: 22))
                                            .frame(width: 52, height: 52)
                                            .foregroundStyle(selected ? .white : tint)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .fill(selected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Theme.elevated))
                                            )
                                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
                                            .scaleEffect(selected ? 1.06 : 1)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(icon)
                                }
                            }
                        }
                    }
                }
                .padding(28)
            }
            .background(Theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let colorName {
            VStack(spacing: 10) {
                FolderArtwork(color: FolderColor(rawValue: colorName.wrappedValue) ?? .terracotta, iconName: iconName, documentCount: previewDocumentCount)
                    .frame(width: 150, height: 118)
                Text(previewName).font(.serif(.headline, weight: .semibold))
            }
        } else {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Theme.elevated)
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                    Image(systemName: iconName ?? "doc.text")
                        .font(.system(size: 40))
                        .foregroundStyle(iconName == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Theme.accent))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(previewName).font(.serif(.headline, weight: .semibold))
            }
        }
    }
}

/// Selettore di destinazione per spostare note e cartelle.
struct MoveSheet: View {
    let title: LocalizedStringKey
    let movingFolder: Folder?
    let currentParentID: UUID?
    let onSelect: (Folder?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.name) private var folders: [Folder]

    private var roots: [Folder] {
        folders.filter { $0.parent == nil && $0.deletedAt == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    Label("Libreria (livello principale)", systemImage: "books.vertical")
                }
                .disabled(currentParentID == nil)

                Section("Cartelle") {
                    OutlineGroup(roots, children: \.outlineChildren) { folder in
                        let disabled = isDisabled(folder)
                        Button {
                            onSelect(folder)
                            dismiss()
                        } label: {
                            Label {
                                Text(folder.name)
                            } icon: {
                                Image(systemName: folder.iconName ?? "folder.fill")
                                    .foregroundStyle(folder.color.color)
                            }
                        }
                        .disabled(disabled)
                        .opacity(disabled ? 0.45 : 1)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
    }

    private func isDisabled(_ folder: Folder) -> Bool {
        if folder.id == currentParentID { return true }
        if let moving = movingFolder {
            return folder.id == moving.id || folder.isDescendant(of: moving)
        }
        return false
    }
}

