import SwiftData
import SwiftUI

// MARK: - Disegno della cartella

/// Retro della cartella con la linguetta.
struct FolderBackShape: Shape {
    func path(in r: CGRect) -> Path {
        let tabWidth = r.width * 0.40
        let tabHeight = r.height * 0.13
        let radius = min(r.width, r.height) * 0.09
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + tabWidth - radius, y: r.minY))
        p.addCurve(
            to: CGPoint(x: r.minX + tabWidth + radius * 1.2, y: r.minY + tabHeight),
            control1: CGPoint(x: r.minX + tabWidth + radius * 0.2, y: r.minY),
            control2: CGPoint(x: r.minX + tabWidth + radius * 0.4, y: r.minY + tabHeight)
        )
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY + tabHeight))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + tabHeight + radius), control: CGPoint(x: r.maxX, y: r.minY + tabHeight))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct FolderArtwork: View {
    let color: FolderColor
    let iconName: String?
    var isHighlighted = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .bottom) {
                FolderBackShape()
                    .fill(LinearGradient(
                        colors: [color.color.mix(with: .black, by: 0.12), color.color.mix(with: .black, by: 0.28)],
                        startPoint: .top, endPoint: .bottom
                    ))

                // Fogli che spuntano dalla cartella.
                RoundedRectangle(cornerRadius: h * 0.05, style: .continuous)
                    .fill(Color(white: 0.93))
                    .frame(width: w * 0.80, height: h * 0.6)
                    .rotationEffect(.degrees(isHighlighted ? -6 : -2.5))
                    .offset(x: -w * 0.02, y: -h * (isHighlighted ? 0.34 : 0.26))
                RoundedRectangle(cornerRadius: h * 0.05, style: .continuous)
                    .fill(.white)
                    .frame(width: w * 0.78, height: h * 0.6)
                    .overlay(alignment: .top) {
                        VStack(spacing: h * 0.045) {
                            ForEach(0..<3, id: \.self) { _ in
                                Capsule().fill(Color(white: 0.85)).frame(height: max(1, h * 0.012))
                            }
                        }
                        .padding(.horizontal, w * 0.08)
                        .padding(.top, h * 0.06)
                    }
                    .rotationEffect(.degrees(isHighlighted ? 4 : 2))
                    .offset(x: w * 0.02, y: -h * (isHighlighted ? 0.31 : 0.23))

                // Fronte.
                RoundedRectangle(cornerRadius: min(w, h) * 0.09, style: .continuous)
                    .fill(LinearGradient(
                        colors: [color.color.mix(with: .white, by: 0.14), color.color],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: min(w, h) * 0.09, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0)], startPoint: .top, endPoint: .center),
                                lineWidth: 1.2
                            )
                    }
                    .overlay {
                        if let iconName {
                            Image(systemName: iconName)
                                .font(.system(size: h * 0.27, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                                .offset(y: h * 0.02)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .frame(height: h * 0.74)
                    .rotation3DEffect(.degrees(isHighlighted ? -14 : 0), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.6)
                    .shadow(color: .black.opacity(0.16), radius: 3, y: -1)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isHighlighted)
        }
        .aspectRatio(1.27, contentMode: .fit)
        .shadow(color: color.color.opacity(0.28), radius: 10, y: 6)
    }
}

// MARK: - Anteprima carta

struct PaperPreview: View {
    let style: PaperStyle

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                let referenceWidth: CGFloat = style.isInfinite ? 640 : PageLayout.pageSize.width
                let scale = size.width / referenceWidth
                cg.scaleBy(x: scale, y: scale)
                let area = CGRect(x: 0, y: 0, width: referenceWidth, height: size.height / scale)
                cg.setFillColor(UIColor.white.cgColor)
                cg.fill(area)
                PaperRenderer.drawPattern(style.pattern, in: area, clip: area, isPage: !style.isInfinite, ctx: cg, lineScale: max(1, 0.55 / scale))
            }
        }
        .background(Color.white)
    }
}

// MARK: - Miniatura nota

struct NoteThumbnail: View {
    let note: Note

    var body: some View {
        Color.white
            .aspectRatio(0.74, contentMode: .fit)
            .overlay(alignment: .top) {
                if let image = ThumbnailCache.image(for: note) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    PaperPreview(style: note.paperStyle)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.black.opacity(0.07)))
            .overlay(alignment: .topLeading) {
                if let icon = note.iconName {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular, in: .circle)
                        .padding(8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if note.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.yellow)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        .padding(10)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if note.paperStyle.isInfinite || note.paperStyle == .pdf {
                    Image(systemName: note.paperStyle == .pdf ? "doc.richtext" : "infinity")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8)
                }
            }
            .shadow(color: .black.opacity(0.10), radius: 10, y: 5)
    }
}

private struct TransitionSource: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

// MARK: - Riquadro nota

struct NoteTile: View {
    @Bindable var note: Note
    @Environment(AppRouter.self) private var router
    @Environment(\.noteTransitionNamespace) private var namespace

    @State private var showRename = false
    @State private var showIcon = false
    @State private var showMove = false
    @State private var confirmDelete = false

    var body: some View {
        Button {
            router.open(note)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                NoteThumbnail(note: note)
                    .modifier(TransitionSource(id: note.id, namespace: namespace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.displayTitle)
                        .font(.serif(.headline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(note.updatedAt.relativeItalian)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(TileButtonStyle())
        .contextMenu { menu }
        .draggable("note:\(note.id.uuidString)") {
            NoteThumbnail(note: note).frame(width: 110)
        }
        .modifier(RenameAlert(isPresented: $showRename, title: "Rinomina nota", current: note.title) { name in
            note.title = name
            note.updatedAt = Date()
            try? note.modelContext?.save()
        })
        .modifier(DoubleConfirmDelete(isPresented: $confirmDelete, itemName: note.displayTitle, isFolder: false) {
            withAnimation { LibraryActions.trash(note) }
        })
        .sheet(isPresented: $showIcon, onDismiss: { try? note.modelContext?.save() }) {
            CustomizeSheet(title: "Icona della nota", iconName: $note.iconName, colorName: nil, previewName: note.displayTitle)
        }
        .sheet(isPresented: $showMove) {
            MoveSheet(title: "Sposta nota", movingFolder: nil, currentParentID: note.folder?.id) { target in
                withAnimation { LibraryActions.move(note, to: target) }
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button { router.open(note) } label: { Label("Apri", systemImage: "arrow.up.forward.app") }
        Button { showIcon = true } label: {
            Label(note.iconName == nil ? "Aggiungi icona" : "Cambia icona", systemImage: "face.smiling")
        }
        Button {
            withAnimation { note.isFavorite.toggle() }
            try? note.modelContext?.save()
        } label: {
            Label(note.isFavorite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti", systemImage: note.isFavorite ? "star.slash" : "star")
        }
        Button { showRename = true } label: { Label("Rinomina", systemImage: "pencil") }
        Button {
            withAnimation { _ = LibraryActions.duplicate(note) }
        } label: { Label("Duplica", systemImage: "plus.square.on.square") }
        Button { showMove = true } label: { Label("Sposta in…", systemImage: "folder") }
        Divider()
        Button(role: .destructive) { confirmDelete = true } label: { Label("Elimina", systemImage: "trash") }
    }
}

// MARK: - Riquadro cartella

struct FolderTile: View {
    @Bindable var folder: Folder
    @Environment(\.modelContext) private var context

    @State private var showRename = false
    @State private var showCustomize = false
    @State private var showMove = false
    @State private var confirmDelete = false
    @State private var isDropTargeted = false

    var body: some View {
        NavigationLink(value: folder) {
            VStack(alignment: .leading, spacing: 10) {
                FolderArtwork(color: folder.color, iconName: folder.iconName, isHighlighted: isDropTargeted)
                    .overlay(alignment: .topTrailing) {
                        if folder.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.yellow)
                                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                                .padding(.top, 22)
                                .padding(.trailing, 10)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.serif(.headline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(folder.itemSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(TileButtonStyle())
        .contextMenu { menu }
        .draggable("folder:\(folder.id.uuidString)") {
            FolderArtwork(color: folder.color, iconName: folder.iconName).frame(width: 120)
        }
        .dropDestination(for: String.self) { items, _ in
            let moved = LibraryActions.handleDrop(items.filter { !$0.hasSuffix(folder.id.uuidString) }, into: folder, context: context)
            return moved
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isDropTargeted) { _, new in new }
        .modifier(RenameAlert(isPresented: $showRename, title: "Rinomina cartella", current: folder.name) { name in
            folder.name = name
            folder.updatedAt = Date()
            try? context.save()
        })
        .modifier(DoubleConfirmDelete(isPresented: $confirmDelete, itemName: folder.name, isFolder: true) {
            withAnimation { LibraryActions.trash(folder) }
        })
        .sheet(isPresented: $showCustomize, onDismiss: { try? context.save() }) {
            CustomizeSheet(title: "Personalizza cartella", iconName: $folder.iconName, colorName: $folder.colorName, previewName: folder.name)
        }
        .sheet(isPresented: $showMove) {
            MoveSheet(title: "Sposta cartella", movingFolder: folder, currentParentID: folder.parent?.id) { target in
                withAnimation { _ = LibraryActions.move(folder, to: target) }
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        Menu {
            ForEach(FolderColor.allCases) { color in
                Button {
                    withAnimation(.spring) { folder.colorName = color.rawValue }
                    try? context.save()
                } label: {
                    Label { Text(color.displayName) } icon: { Image(uiImage: color.menuSwatch) }
                }
            }
        } label: {
            Label("Colore", systemImage: "paintpalette")
        }
        Button { showCustomize = true } label: {
            Label(folder.iconName == nil ? "Aggiungi icona" : "Cambia icona", systemImage: "face.smiling")
        }
        Button {
            withAnimation { folder.isFavorite.toggle() }
            try? context.save()
        } label: {
            Label(folder.isFavorite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti", systemImage: folder.isFavorite ? "star.slash" : "star")
        }
        Button { showRename = true } label: { Label("Rinomina", systemImage: "pencil") }
        Button { showMove = true } label: { Label("Sposta in…", systemImage: "folder") }
        Divider()
        Button(role: .destructive) { confirmDelete = true } label: { Label("Elimina", systemImage: "trash") }
    }
}
