import Foundation
import SwiftData
import Observation

/// Funzioni attivate in fase di compilazione.
///
/// La sincronizzazione iCloud richiede un account Apple Developer (entitlement CloudKit), quindi è
/// esclusa dalle build normali. Per riattivarla vedi il README: basta aggiungere `ICLOUD_SYNC` alle
/// "Active Compilation Conditions" e collegare `Config/BetterNotes.entitlements`.
enum BuildFeatures {
    #if ICLOUD_SYNC
    static let iCloudSync = true
    #else
    static let iCloudSync = false
    #endif
}

/// Crea il contenitore SwiftData. La sincronizzazione iCloud (CloudKit) è facoltativa
/// e viene applicata all'avvio dell'app in base all'impostazione dell'utente.
@Observable
final class Persistence {
    static let cloudContainerID = "iCloud.com.romeo.BetterNotes"

    let container: ModelContainer
    let isCloudSyncActive: Bool
    let cloudError: String?

    init() {
        let schema = Schema([Folder.self, Note.self])
        let wantsCloud = BuildFeatures.iCloudSync && UserDefaults.standard.bool(forKey: SettingsKey.iCloudSync)
        var cloudError: String?

        #if ICLOUD_SYNC
        if wantsCloud {
            do {
                let config = ModelConfiguration(
                    "BetterNotes",
                    schema: schema,
                    cloudKitDatabase: .private(Self.cloudContainerID)
                )
                container = try ModelContainer(for: schema, configurations: [config])
                isCloudSyncActive = true
                self.cloudError = nil
                return
            } catch {
                cloudError = error.localizedDescription
            }
        }
        #else
        _ = wantsCloud
        #endif

        do {
            let config = ModelConfiguration("BetterNotes", schema: schema, cloudKitDatabase: .none)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Ultima risorsa: archivio in memoria, così l'app resta utilizzabile.
            let config = ModelConfiguration("BetterNotes", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            container = try! ModelContainer(for: schema, configurations: [config])
            cloudError = (cloudError.map { $0 + "\n" } ?? "") + error.localizedDescription
        }
        isCloudSyncActive = false
        self.cloudError = cloudError
    }

    var iCloudAccountAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}
