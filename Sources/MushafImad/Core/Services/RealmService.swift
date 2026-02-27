import Foundation
import RealmSwift

public enum RealmServiceError: LocalizedError {
    case bundledRealmNotFound
    case configurationMissing
    case notInitialized
    case configurationMismatch
    
    public var errorDescription: String? {
        switch self {
        case .bundledRealmNotFound: return "قاعدة بيانات المصحف المدمجة غير موجودة."
        case .configurationMissing: return "إعدادات Realm مفقودة."
        case .notInitialized: return "يجب تهيئة RealmService أولاً."
        case .configurationMismatch: return "تم تهيئة الخدمة بالفعل بإعدادات مختلفة."
        }
    }
}

@MainActor
public final class RealmService {
    public enum Configuration: Equatable {
        case bundled
        case custom(url: URL)
        case inMemory(identifier: String)
    }
    
    public static let shared = RealmService()
    private var realm: Realm?
    private var realmConfig: Realm.Configuration?
    private var activeConfigType: Configuration?

    public var isInitialized: Bool { realm != nil }

    public init() {}

    public func initialize(with configType: Configuration = .bundled) throws {
        // منع إعادة التهيئة بإعدادات مختلفة (ملاحظة الـ AI رقم 30-31)
        if let active = activeConfigType, active != configType {
            throw RealmServiceError.configurationMismatch
        }
        if realm != nil { return }
        
        let fileManager = FileManager.default
        var config = Realm.Configuration()
        
        switch configType {
        case .bundled:
            guard let bundledURL = Bundle.mushafResources.url(forResource: "quran", withExtension: "realm") else {
                throw RealmServiceError.bundledRealmNotFound
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
        
        // معالجة الـ Migration (ملاحظة الـ AI رقم 56-59)
        config.schemaVersion = 24
        config.migrationBlock = { migration, oldSchemaVersion in
            if oldSchemaVersion < 24 {
                // Realm يقوم بمعالجة إضافة الحقول الجديدة تلقائياً
                print("[RealmService] Migrating schema from \(oldSchemaVersion) to 24")
            }
        }
        
        self.realmConfig = config
        self.realm = try Realm(configuration: config)
        self.activeConfigType = configType
    }

    // الدالة الأساسية لجلب السور
    public func fetchAllChaptersAsync() async throws -> [Chapter] {
        guard let config = realmConfig else { throw RealmServiceError.notInitialized }
        return try await Task.detached {
            let realm = try Realm(configuration: config)
            return Array(realm.objects(Chapter.self).sorted(byKeyPath: "number").freeze())
        }.value
    }

    // --- الدوال التي كانت ناقصة وتسببت في الاعتراض (ملاحظة رقم 114-115) ---

    public func getChapterForPage(_ page: Int) -> Chapter? {
        return realm?.objects(Chapter.self).filter("ANY verses.page1441.number == %d", page).first?.freeze()
    }

    public func getVersesForPage(_ pageNumber: Int) -> [Verse] {
        guard let realm = realm else { return [] }
        // البحث عن الآيات التي تنتمي لرقم الصفحة المحدد
        let verses = realm.objects(Verse.self).filter("page1441.number == %d", pageNumber)
        return Array(verses.freeze())
    }

    public func getRandomAyah(for date: Date) -> Verse? {
        guard let realm = realm else { return nil }
        let allVerses = realm.objects(Verse.self)
        guard allVerses.count > 0 else { return nil }
        
        // اختيار آية ثابتة بناءً على تاريخ اليوم (Deterministic Selection)
        let calendar = Calendar.current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let index = dayOfYear % allVerses.count
        return allVerses[index].freeze()
    }
}
