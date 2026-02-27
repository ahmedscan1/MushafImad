import Foundation
import RealmSwift

/// Facade around the Realm database that powers Quran metadata.
/// Refactored to support modular configurations (Bundled, Custom, In-Memory).
@MainActor
public final class RealmService {
    
    // 1. إضافة الـ Configuration Enum المطلوب في المهمة
    public enum Configuration {
        case bundled
        case custom(url: URL)
        case inMemory(identifier: String)
    }
    
    public static let shared = RealmService()
    
    private var realm: Realm?
    private var realmConfig: Realm.Configuration?
    
    // جعل الـ init عام (public) للسماح بإنشاء نسخ معزولة عند الحاجة
    public init() {}
    
    // MARK: - Initialization
    
    /// Initializes Realm with a specific configuration. 
    /// Defaults to .bundled for backward compatibility.
    public func initialize(with configType: Configuration = .bundled) throws {
        // إذا كان تم التهيئة مسبقاً بنفس الإعدادات، لا نكرر العملية
        if realm != nil { return }
        
        let fileManager = FileManager.default
        let finalURL: URL?
        let identifier: String?
        
        switch configType {
        case .bundled:
            // الكود الأصلي: البحث عن الملف في الـ Bundle ونسخه للمسار القابل للكتابة
            guard let bundledURL = Bundle.mushafResources.url(forResource: "quran", withExtension: "realm") else {
                throw NSError(domain: "RealmService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bundled realm not found"])
            }
            let appSupportURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let writableURL = appSupportURL.appendingPathComponent("quran.realm")
            
            if !fileManager.fileExists(atPath: writableURL.path) {
                try fileManager.copyItem(at: bundledURL, to: writableURL)
            }
            finalURL = writableURL
            identifier = nil
            
        case .custom(let url):
            finalURL = url
            identifier = nil
            
        case .inMemory(let id):
            finalURL = nil
            identifier = id
        }
        
        // بناء الـ Realm Configuration
        var config = Realm.Configuration()
        if let url = finalURL {
            config.fileURL = url
        } else if let id = identifier {
            config.inMemoryIdentifier = id
        }
        
        config.schemaVersion = 24
        config.migrationBlock = { migration, oldSchemaVersion in
            if oldSchemaVersion < 24 { /* Lightweight migration */ }
        }
        
        self.realmConfig = config
        self.realm = try Realm(configuration: config)
    }
    
    // MARK: - Updated Methods for Thread Safety
    
    public var isInitialized: Bool {
        return realm != nil
    }

    // تعديل fetchAllChaptersAsync لاستخدام الـ config الحالي
    public func fetchAllChaptersAsync() async throws -> [Chapter] {
        if !isInitialized { try initialize() }
        guard let config = realmConfig else {
            throw NSError(domain: "RealmService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Configuration missing"])
        }
        
        return try await Task.detached {
            let realm = try Realm(configuration: config)
            let results = realm.objects(Chapter.self).sorted(byKeyPath: "number")
            return Array(results.freeze())
        }.value
    }

    // ... (بقية العمليات مثل getChapter و getPage تظل كما هي لكنها ستعتمد على الـ realm الذي تم تهيئته)
}
