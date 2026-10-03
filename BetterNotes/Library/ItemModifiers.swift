import SwiftUI

/// Alert con campo di testo per rinominare.
struct RenameAlert: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let current: String
    let onRename: (String) -> Void
    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                TextField("Nome", text: $text)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                Button("Annulla", role: .cancel) {}
                Button("Rinomina") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { onRename(trimmed) }
                }
            }
            .onChange(of: isPresented) { _, presented in
                if presented { text = current }
            }
    }
}

/// Eliminazione con doppia conferma: prima un dialogo, poi un avviso definitivo.
struct DoubleConfirmDelete: ViewModifier {
    @Binding var isPresented: Bool
    let itemName: String
    let isFolder: Bool
    let onConfirm: () -> Void
    @State private var showSecondConfirmation = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Eliminare “\(itemName)”?", isPresented: $isPresented, titleVisibility: .visible) {
                Button(isFolder ? "Elimina cartella" : "Elimina nota", role: .destructive) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showSecondConfirmation = true }
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text(isFolder
                     ? "La cartella e tutto il suo contenuto verranno spostati nel Cestino."
                     : "La nota verrà spostata nel Cestino.")
            }
            .alert("Sei sicuro?", isPresented: $showSecondConfirmation) {
                Button("Annulla", role: .cancel) {}
                Button("Sì, elimina", role: .destructive, action: onConfirm)
            } message: {
                Text("Conferma ancora una volta. Potrai recuperare “\(itemName)” dal Cestino entro \(LibraryActions.trashRetentionDays) giorni, poi verrà eliminata per sempre.")
            }
    }
}

/// Stile dei riquadri della libreria: leggera compressione alla pressione.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var count: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.serif(.title2, weight: .semibold))
            if let count {
                Text("\(count)")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.06), in: Capsule())
            }
            Spacer()
            if let subtitle {
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

extension Date {
    var relativeItalian: String {
        let calendar = Calendar.current
        let time = formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(self) { return "Oggi, \(time)" }
        if calendar.isDateInYesterday(self) { return "Ieri, \(time)" }
        if let days = calendar.dateComponents([.day], from: self, to: Date()).day, days < 7 {
            return formatted(.dateTime.weekday(.wide)).capitalized + ", \(time)"
        }
        return formatted(.dateTime.day().month(.abbreviated).year())
    }
}
