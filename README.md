# BetterNotes

App iPadOS nativa (SwiftUI + PencilKit, iPadOS 26) per prendere appunti scolastici con Apple Pencil.

## Avvio

1. Apri `BetterNotes.xcodeproj` con Xcode 26.
2. In *Signing & Capabilities* scegli il tuo Team (necessario per installarla su un iPad reale).
3. Esegui su un iPad o sul simulatore.

> Nel simulatore non c'è l'Apple Pencil: disattiva **Favorisci Apple Pencil** dal menù rapido dell'editor per poter scrivere con il mouse/dito.

## Lingue

L'app è in **italiano** e **inglese** e segue la lingua del dispositivo (per le altre lingue usa l'inglese).
Si può scegliere una lingua solo per BetterNotes da *Impostazioni di iPadOS › App › BetterNotes › Lingua*.

I testi stanno in `BetterNotes/Localizable.xcstrings` (le chiavi sono le frasi italiane). Xcode aggiunge da solo
le nuove stringhe al catalogo quando compili: basta scriverne la traduzione inglese nell'editor del catalogo.
Ogni voce ha anche il valore italiano esplicito, altrimenti Xcode non genera `it.lproj` e iPadOS non mostra
l'italiano tra le lingue dell'app.

## Sincronizzazione iCloud (disattivata in questa build)

La sincronizzazione iCloud richiede un account Apple Developer a pagamento (entitlement CloudKit), quindi è
**esclusa dalla compilazione**: l'app si compila ed esporta con un account gratuito e in Impostazioni la voce
iCloud è visibile ma disattivata, con la spiegazione. Il codice resta nel progetto, protetto dal flag `ICLOUD_SYNC`.

Per riattivarla:

1. *Build Settings → Swift Compiler – Custom Flags → Active Compilation Conditions*: aggiungi `ICLOUD_SYNC`
   (Debug e Release).
2. *Build Settings → Code Signing Entitlements*: imposta `Config/BetterNotes.entitlements`.
3. *Signing & Capabilities*: aggiungi **iCloud** → spunta **CloudKit** e crea il container `iCloud.com.romeo.BetterNotes`
   (se cambi il bundle id, aggiorna anche `Persistence.cloudContainerID` e l'entitlements), poi
   **Background Modes → Remote notifications**.
4. Nell'app: *Impostazioni → Sincronizza con iCloud*, poi chiudi e riapri l'app.

## Struttura

| Cartella | Contenuto |
| --- | --- |
| `App/` | Entry point, tema (crema / grigio scuro, font New York), router, persistenza, impostazioni |
| `Models/` | `Folder`, `Note` (SwiftData), stili carta, colori, icone, azioni (cestino, spostamenti) |
| `Library/` | Home, card di cartelle/note, menu contestuali, nuova nota, preferiti, recenti, cestino |
| `Editor/` | Editor nota, pannello strumenti fluttuante, menù rapido, esportazione |
| `Editor/Canvas/` | Tela PencilKit, carta vettoriale, inchiostro con stabilizzazione in tempo reale (`LiveInk`), immagini, pagine |
| `Import/` | Importazione PDF e Word (.docx/.doc → PDF impaginato A4) |
| `Settings/` | Impostazioni |
