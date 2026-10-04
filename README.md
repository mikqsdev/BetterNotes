# BetterNotes

App iPadOS nativa (SwiftUI + PencilKit, iPadOS 26) per prendere appunti scolastici con Apple Pencil.

## Avvio

1. Apri `BetterNotes.xcodeproj` con Xcode 26.
2. In *Signing & Capabilities* scegli il tuo Team (necessario per installarla su un iPad reale).
3. Esegui su un iPad o sul simulatore.

> Nel simulatore non c'è l'Apple Pencil: disattiva **Favorisci Apple Pencil** dal menù rapido dell'editor per poter scrivere con il mouse/dito.

## Sincronizzazione iCloud (facoltativa)

È già predisposta (SwiftData + CloudKit). Per attivarla su dispositivo:

1. In *Signing & Capabilities* aggiungi **iCloud** → spunta **CloudKit** e crea il container `iCloud.com.romeo.BetterNotes`
   (se cambi il bundle id, aggiorna anche `Persistence.cloudContainerID` e `Config/BetterNotes.entitlements`).
2. Aggiungi **Background Modes → Remote notifications** (già presente in `Config/Info.plist`).
3. Nell'app: *Impostazioni → Sincronizza con iCloud*, poi chiudi e riapri l'app.

## Struttura

| Cartella | Contenuto |
| --- | --- |
| `App/` | Entry point, tema (crema / grigio scuro, font New York), router, persistenza, impostazioni |
| `Models/` | `Folder`, `Note` (SwiftData), stili carta, colori, icone, azioni (cestino, spostamenti) |
| `Library/` | Home, card di cartelle/note, menu contestuali, nuova nota, preferiti, recenti, cestino |
| `Editor/` | Editor nota, pannello strumenti fluttuante, menù rapido, esportazione |
| `Editor/Canvas/` | Tela PencilKit, carta vettoriale a tile, stabilizzazione tratto, immagini |
| `Import/` | Importazione PDF e Word (.docx/.doc → PDF impaginato A4) |
| `Settings/` | Impostazioni |
