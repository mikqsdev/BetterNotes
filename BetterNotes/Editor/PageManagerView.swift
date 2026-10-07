import SwiftUI

/// Gestione delle pagine di una nota a fogli: anteprime, aggiunta, riordino (tenendo premuto e trascinando)
/// e altre azioni dal menu contestuale (tenendo premuto).
struct PageManagerView: View {
    @Bindable var controller: EditorController
    /// Condivide un file esportato (gestito dall'editor, dopo la chiusura del popover).
    var onShare: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeletion: Int?
    @State private var dropTarget: Int?

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 160), spacing: 18, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        ForEach(0..<controller.pageCount, id: \.self) { index in
                            pageCell(index)
                        }
                        addCell
                    }
                    Label("Tieni premuto su una pagina per spostarla o per vedere altre opzioni.", systemImage: "hand.tap")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: controller.pageCount)
            }
            .background(Theme.background)
            .navigationTitle(controller.pageCount == 1 ? "1 pagina" : "\(controller.pageCount) pagine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if controller.pageStyle != .pdf {
                        Menu {
                            Picker("Stile delle pagine", selection: Binding(get: { controller.pageStyle }, set: { controller.changePaperStyle(to: $0) })) {
                                ForEach(PaperStyle.pageStyles) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                        } label: {
                            Label("Stile carta", systemImage: "square.grid.3x3")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { controller.insertPage(at: controller.currentPage) } label: {
                            Label("Dopo la pagina corrente", systemImage: "arrow.turn.down.right")
                        }
                        Button { controller.insertPage(at: controller.currentPage - 1) } label: {
                            Label("Prima della pagina corrente", systemImage: "arrow.turn.up.right")
                        }
                        Button { controller.insertPage() } label: {
                            Label("In fondo", systemImage: "arrow.down.to.line")
                        }
                    } label: {
                        Label("Aggiungi pagina", systemImage: "plus")
                    }
                }
            }
        }
        .frame(width: 560, height: 640)
        .presentationCompactAdaptation(.popover)
        .alert("Eliminare la pagina \((pendingDeletion ?? 0) + 1)?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
            Button("Annulla", role: .cancel) {}
            Button("Elimina", role: .destructive) {
                if let index = pendingDeletion { controller.deletePage(index) }
            }
        } message: {
            Text("La pagina e tutto ciò che contiene verranno eliminati. Puoi annullare con il tasto Annulla dell'editor.")
        }
    }

    private func pageCell(_ index: Int) -> some View {
        let isCurrent = controller.currentPage == index + 1
        return VStack(spacing: 8) {
            Group {
                if let image = controller.pageThumbnail(index) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.white.aspectRatio(0.707, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isCurrent ? Theme.accent : Color.black.opacity(0.1), lineWidth: isCurrent ? 3 : 1)
            )
            .overlay(alignment: .leading) {
                if dropTarget == index {
                    Capsule().fill(Theme.accent).frame(width: 4).padding(.vertical, 6).offset(x: -11)
                }
            }
            .shadow(color: .black.opacity(0.1), radius: 6, y: 3)

            Text("\(index + 1)")
                .font(.subheadline.monospacedDigit().weight(isCurrent ? .bold : .medium))
                .foregroundStyle(isCurrent ? Theme.accent : .secondary)
        }
        .contentShape(.rect)
        .onTapGesture {
            controller.goToPage(index + 1)
            dismiss()
        }
        .draggable("page:\(index)") {
            Group {
                if let image = controller.pageThumbnail(index) {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Color.white.aspectRatio(0.707, contentMode: .fit)
                }
            }
            .frame(width: 110)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first, payload.hasPrefix("page:"), let source = Int(payload.dropFirst(5)) else { return false }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                controller.movePage(from: source, to: index)
            }
            return true
        } isTargeted: { targeted in
            if targeted { dropTarget = index } else if dropTarget == index { dropTarget = nil }
        }
        .contextMenu {
            Button { controller.goToPage(index + 1); dismiss() } label: { Label("Vai alla pagina", systemImage: "arrow.right.doc.on.clipboard") }
            Divider()
            Button { controller.insertPage(at: index) } label: { Label("Inserisci pagina prima", systemImage: "arrow.turn.up.right") }
            Button { controller.insertPage(at: index + 1) } label: { Label("Inserisci pagina dopo", systemImage: "arrow.turn.down.right") }
            Button { controller.duplicatePage(index) } label: { Label("Duplica", systemImage: "plus.square.on.square") }
            if index > 0 {
                Button { controller.movePage(from: index, to: index - 1) } label: { Label("Sposta prima", systemImage: "arrow.left") }
            }
            if index < controller.pageCount - 1 {
                Button { controller.movePage(from: index, to: index + 1) } label: { Label("Sposta dopo", systemImage: "arrow.right") }
            }
            Divider()
            Button {
                if let url = controller.exportPageImage(index) { onShare(url) }
            } label: { Label("Esporta come immagine", systemImage: "photo") }
            Button { controller.clearPage(index) } label: { Label("Svuota pagina", systemImage: "eraser") }
            if controller.pageCount > 1 {
                Button(role: .destructive) { pendingDeletion = index } label: { Label("Elimina pagina", systemImage: "trash") }
            }
        }
    }

    private var addCell: some View {
        Button {
            controller.insertPage()
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    .aspectRatio(0.707, contentMode: .fit)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                Text("Nuova").font(.subheadline.weight(.medium)).foregroundStyle(Theme.accent)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aggiungi pagina in fondo")
    }
}
