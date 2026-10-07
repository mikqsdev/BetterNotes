import Observation
import SwiftData
import SwiftUI

/// Stato del trascinamento di una cartella nella barra laterale.
@MainActor
@Observable
final class SidebarDragModel {
    enum Zone { case before, into, after }

    var rowFrames: [UUID: CGRect] = [:]
    /// Istanza della riga che ha registrato la cornice: quando una cartella cambia posizione nell'albero
    /// la nuova riga compare prima che la vecchia scompaia, e la vecchia non deve cancellare la cornice nuova.
    var frameOwners: [UUID: UUID] = [:]
    var draggingID: UUID?
    var location: CGPoint = .zero
    var target: (id: UUID, zone: Zone)?
    /// Cornice globale della barra laterale (le celle della List non condividono spazi di coordinate con nome).
    var containerFrame: CGRect = .zero
}

/// Albero delle cartelle nella barra laterale.
/// Tieni premuta una cartella e trascinala: rilasciala sopra o sotto un'altra per riordinarla,
/// oppure al centro di una cartella per spostarla al suo interno.
struct SidebarFolderTree: View {
    let folders: [Folder]
    @Binding var expanded: Set<UUID>

    var body: some View {
        ForEach(folders) { folder in
            SidebarFolderBranch(folder: folder, expanded: $expanded)
        }
    }
}

private struct SidebarFolderBranch: View {
    let folder: Folder
    @Binding var expanded: Set<UUID>

    var body: some View {
        if let children = folder.outlineChildren {
            DisclosureGroup(isExpanded: Binding(
                get: { expanded.contains(folder.id) },
                set: { isOpen in
                    if isOpen { expanded.insert(folder.id) } else { expanded.remove(folder.id) }
                }
            )) {
                // AnyView interrompe la ricorsione dei tipi delle viste annidate.
                AnyView(SidebarFolderTree(folders: children, expanded: $expanded))
            } label: {
                SidebarFolderRow(folder: folder, expanded: $expanded)
            }
        } else {
            SidebarFolderRow(folder: folder, expanded: $expanded)
        }
    }
}

private struct SidebarFolderRow: View {
    let folder: Folder
    @Binding var expanded: Set<UUID>
    @Environment(\.modelContext) private var context
    @Environment(SidebarDragModel.self) private var drag
    @State private var isDropTargeted = false
    @State private var instanceID = UUID()

    private var isDragged: Bool { drag.draggingID == folder.id }
    private var zone: SidebarDragModel.Zone? {
        guard let target = drag.target, target.id == folder.id else { return nil }
        return target.zone
    }

    var body: some View {
        Label {
            Text(folder.name).lineLimit(1)
        } icon: {
            Image(systemName: folder.iconName ?? "folder.fill")
                .foregroundStyle(folder.color.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .opacity(isDragged ? 0.35 : 1)
        .tag(SidebarItem.folder(folder.id))
        .background {
            if zone == .into || isDropTargeted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accent.opacity(0.22))
                    .padding(.horizontal, -8)
                    .padding(.vertical, -4)
            }
        }
        .overlay(alignment: zone == .after ? .bottom : .top) {
            if zone == .before || zone == .after {
                Capsule()
                    .fill(Theme.accent)
                    .frame(height: 3)
                    .offset(y: zone == .after ? 8 : -8)
            }
        }
        .animation(.easeOut(duration: 0.12), value: zone)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            drag.rowFrames[folder.id] = frame
        }
        .onDisappear { drag.rowFrames[folder.id] = nil }
        .gesture(reorderGesture)
        // Note trascinate dalla Libreria sopra una cartella della barra laterale.
        .dropDestination(for: String.self) { items, _ in
            let moved = LibraryActions.handleDrop(items.filter { !$0.hasSuffix(folder.id.uuidString) }, into: folder, context: context)
            if moved { expanded.insert(folder.id) }
            return moved
        } isTargeted: { isDropTargeted = $0 }
    }

    private var reorderGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .first(true):
                    if drag.draggingID == nil {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            drag.draggingID = folder.id
                            drag.location = drag.rowFrames[folder.id].map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero
                        }
                    }
                case .second(true, let dragValue?):
                    drag.draggingID = folder.id
                    drag.location = dragValue.location
                    updateTarget(at: dragValue.location)
                default:
                    break
                }
            }
            .onEnded { _ in
                if let target = drag.target, let destination = LibraryActions.folder(withID: target.id, context: context) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        switch target.zone {
                        case .into:
                            if LibraryActions.move(folder, to: destination) { expanded.insert(destination.id) }
                        case .before:
                            LibraryActions.place(folder, nextTo: destination, after: false)
                        case .after:
                            LibraryActions.place(folder, nextTo: destination, after: true)
                        }
                    }
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    drag.draggingID = nil
                    drag.target = nil
                }
            }
    }

    private func updateTarget(at point: CGPoint) {
        let candidate = drag.rowFrames.first { id, frame in
            id != folder.id && point.y >= frame.minY - 4 && point.y <= frame.maxY + 4
        }
        guard let (id, frame) = candidate,
              let destination = LibraryActions.folder(withID: id, context: context),
              !destination.isDescendant(of: folder) else {
            if drag.target != nil { drag.target = nil }
            return
        }
        let fraction = (point.y - frame.minY) / max(frame.height, 1)
        let zone: SidebarDragModel.Zone = fraction < 0.3 ? .before : (fraction > 0.7 ? .after : .into)
        if drag.target?.id != id || drag.target?.zone != zone {
            drag.target = (id, zone)
        }
    }
}

/// Etichetta che segue il dito durante il trascinamento.
struct SidebarDragGhost: View {
    @Environment(SidebarDragModel.self) private var drag
    let folders: [Folder]

    var body: some View {
        if let id = drag.draggingID, let folder = folders.first(where: { $0.id == id }) {
            Label {
                Text(folder.name).lineLimit(1).font(.serif(.body, weight: .semibold))
            } icon: {
                Image(systemName: folder.iconName ?? "folder.fill").foregroundStyle(folder.color.color)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            .position(
                x: (drag.rowFrames[id]?.midX ?? drag.location.x) - drag.containerFrame.minX,
                y: drag.location.y - drag.containerFrame.minY
            )
            .allowsHitTesting(false)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }
}
