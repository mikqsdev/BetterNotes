import Foundation

/// Raccolta di icone (SF Symbols, la libreria di icone ufficiale Apple) organizzata per materia.
struct IconCategory: Identifiable {
    let name: String
    let icons: [String]
    var id: String { name }
}

enum IconLibrary {
    static let categories: [IconCategory] = [
        IconCategory(name: "Scuola", icons: [
            "graduationcap.fill", "backpack.fill", "books.vertical.fill", "book.closed.fill",
            "text.book.closed.fill", "book.fill", "bookmark.fill", "studentdesk",
            "pencil.and.ruler.fill", "ruler.fill", "highlighter", "paperclip",
            "calendar", "checklist", "list.bullet.clipboard.fill", "doc.text.fill",
            "folder.fill", "tray.full.fill", "archivebox.fill", "pencil.tip",
        ]),
        IconCategory(name: "Matematica e scienze", icons: [
            "function", "x.squareroot", "sum", "percent", "divide", "plus.forwardslash.minus",
            "angle", "chart.xyaxis.line", "chart.bar.fill", "chart.pie.fill",
            "atom", "flask.fill", "testtube.2", "microbe.fill", "leaf.fill", "tree.fill",
            "bolt.fill", "magnet", "scalemass.fill", "thermometer.medium",
            "lungs.fill", "brain.head.profile", "heart.fill", "cross.case.fill", "pills.fill",
            "globe.europe.africa.fill", "moon.stars.fill", "sun.max.fill", "drop.fill", "flame.fill",
        ]),
        IconCategory(name: "Lettere e lingue", icons: [
            "character.book.closed.fill", "text.quote", "quote.bubble.fill", "textformat",
            "character", "a.book.closed.fill", "globe", "bubble.left.and.bubble.right.fill",
            "envelope.fill", "newspaper.fill", "scroll.fill", "signature",
        ]),
        IconCategory(name: "Storia e società", icons: [
            "building.columns.fill", "crown.fill", "shield.fill", "flag.fill",
            "map.fill", "mappin.and.ellipse", "location.north.fill", "building.2.fill",
            "person.3.fill", "person.fill", "dollarsign.circle.fill", "briefcase.fill",
            "eurosign.circle.fill", "banknote.fill", "hammer.fill", "scale.3d",
        ]),
        IconCategory(name: "Arte e tecnologia", icons: [
            "paintpalette.fill", "paintbrush.pointed.fill", "theatermasks.fill", "music.note",
            "music.quarternote.3", "pianokeys", "guitars.fill", "camera.fill", "film.fill",
            "photo.fill", "desktopcomputer", "laptopcomputer", "cpu.fill",
            "chevron.left.forwardslash.chevron.right", "terminal.fill", "gearshape.fill",
            "wrench.and.screwdriver.fill", "cube.fill", "gamecontroller.fill", "puzzlepiece.fill",
        ]),
        IconCategory(name: "Sport e tempo libero", icons: [
            "sportscourt.fill", "figure.run", "soccerball", "basketball.fill", "tennis.racket",
            "bicycle", "trophy.fill", "medal.fill", "figure.pool.swim", "dumbbell.fill",
            "airplane", "car.fill", "tram.fill", "house.fill", "cup.and.saucer.fill", "fork.knife",
        ]),
        IconCategory(name: "Simboli", icons: [
            "star.fill", "sparkles", "lightbulb.fill", "target", "flag.checkered",
            "exclamationmark.triangle.fill", "questionmark.circle.fill", "checkmark.seal.fill",
            "clock.fill", "hourglass", "bell.fill", "tag.fill", "pin.fill", "lock.fill", "key.fill",
            "pawprint.fill", "hare.fill", "tortoise.fill", "bird.fill", "fish.fill",
            "ladybug.fill", "cloud.fill", "snowflake", "mountain.2.fill", "heart.circle.fill",
        ]),
    ]

    static var all: [String] { categories.flatMap(\.icons) }
}
