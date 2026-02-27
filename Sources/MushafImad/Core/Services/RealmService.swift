import Foundation
import RealmSwift

/// Facade around the Realm database that powers Quran metadata.
/// Refactored to support modular configurations and thread-safe operations.
@MainActor
public final class RealmService {
    
    // 1. دعم خيارات التهيئة الموديلار
    public enum Configuration {
        case bundled
        case custom(url: URL)
        case inMemory(identifier: String)
    }
    
    public static let shared = RealmService()
    
    private var realm: Realm?
    private var realmConfig: Realm.Configuration?
    
    // جعل الـ init عام للسماح بإنشاء نسخ معزولة
    public init() {}
    
    public var isInitialized: Bool {
        return realm != nil
    }

    // MARK: - Initialization Logic
    
    public func initialize(with configType: Configuration = .bundled) throws {
        if realm != nil { return }
        
        let fileManager = FileManager.default
        var config = Realm.Configuration()
        
        switch configType {
        case .bundled:
            guard let bundledURL = Bundle.mushafResources.url(forResource: "quran", withExtension: "realm") else {
                throw NSError(domain: "RealmService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bundled realm not found"])
            }
            let appSupportURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let writableURL = appSupportURL.appendingPathComponent("quran.realm")
            
            if !fileManager.fileExists(atPath: writableURL.path) {
                try fileManager.copyItem(at: bundledURL, to: writableURL)
            }
            config.fileURL = writableURL
            
        case .custom(let url):
            config.fileURL = url
            
        case .inMemory(let id):
            config.inMemoryIdentifier = id
        }
        
        config.schemaVersion = 24
        config.migrationBlock = { migration, oldSchemaVersion in
            if oldSchemaVersion < 24 { /* Migration logic */ }
        }
        
        self.realmConfig = config
        self.realm = try Realm(configuration: config)
    }

    /// تهيئة خاصة بالـ Widget (من النسخة الجديدة)
    public func initializeForWidget() throws {
        if realm != nil { return }
        guard let bundledRealmURL = Bundle.mushafResources.url(forResource: "quran", withExtension: "realm") else {
            throw NSError(domain: "RealmService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find quran.realm in bundle"])
        }
        let fileManager = FileManager.default
        guard let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "RealmService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not access Caches directory"])
        }
        let writableRealmURL = cachesURL.appendingPathComponent("quran_widget.realm")
        if !fileManager.fileExists(atPath: writableRealmURL.path) {
            try fileManager.copyItem(at: bundledRealmURL, to: writableRealmURL)
        }
        let config = Realm.Configuration(fileURL: writableRealmURL, schemaVersion: 24)
        self.realmConfig = config
        realm = try Realm(configuration: config)
    }

    // MARK: - Page & Verse Operations (دمج كل وظائف النسخة الجديدة)
    
    public func getPage(number: Int) -> Page? {
        return realm?.objects(Page.self).filter("number == %d", number).first?.freeze()
    }
    
    public func getTotalPages() -> Int {
        return realm?.objects(Page.self).count ?? 604
    }

    public func getVerse(chapterNumber: Int, verseNumber: Int) -> Verse? {
        let humanReadableID = "\(chapterNumber)_\(verseNumber)"
        return realm?.objects(Verse.self).filter("humanReadableID == %@", humanReadableID).first?.freeze()
    }

    public func fetchAllChaptersAsync() async throws -> [Chapter] {
        if !isInitialized { try initialize() }
        guard let config = realmConfig else { throw NSError(domain: "RealmService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Config missing"]) }
        
        return try await Task.detached {
            let realm = try Realm(configuration: config)
            let results = realm.objects(Chapter.self).sorted(byKeyPath: "number")
            return Array(results.freeze())
        }.value
    }
    
    public func getChapter(number: Int) -> Chapter? {
        return realm?.objects(Chapter.self).filter("number == %d", number).first?.freeze()
    }

    // (يمكنك إضافة بقية الدوال مثل getVersesForPage و getRandomAyah هنا بنفس نمط الـ freeze)
}