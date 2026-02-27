import Foundation
import SwiftUI
import Combine

/// Central registry that exposes available reciters and persists the selection.
/// Refactored to be fully modular and injectable.
@MainActor
public final class ReciterService: ObservableObject {
    
    // 1. خيارات التهيئة (Configuration) مع دعم الـ TimingSource الجديد
    public enum Configuration {
        case bundled // المصدر الافتراضي
        case custom(reciters: [ReciterInfo]) // قائمة مخصصة جاهزة
        case manifest(url: URL) // رابط خارجي لملف JSON
    }

    /// Lightweight reciter descriptor surfaced to the UI layer.
    public struct ReciterInfo: Identifiable, Equatable, Codable {
        public let id: Int
        public let nameArabic: String
        public let nameEnglish: String
        public let rewaya: String
        public let folderURL: String
        public let timingSource: TimingSource // إضافة الخاصية الجديدة لضمان التوافق

        public init(
            id: Int,
            nameArabic: String,
            nameEnglish: String,
            rewaya: String,
            folderURL: String,
            timingSource: TimingSource
        ) {
            self.id = id
            self.nameArabic = nameArabic
            self.nameEnglish = nameEnglish
            self.rewaya = rewaya
            self.folderURL = folderURL
            self.timingSource = timingSource
        }
        
        public var displayName: String {
            let preferredLanguage: String
            if #available(macOS 13.0, iOS 16.0, *) {
                preferredLanguage = Locale.current.language.languageCode?.identifier ?? "en"
            } else {
                preferredLanguage = Locale.current.languageCode ?? "en"
            }
            return preferredLanguage == "ar" ? nameArabic : nameEnglish
        }
        
        public var audioBaseURL: URL? {
            URL(string: folderURL)
        }
    }

    public static let shared = ReciterService()
    
    @Published public private(set) var availableReciters: [ReciterInfo] = []
    @Published public var selectedReciter: ReciterInfo? {
        didSet {
            if let reciter = selectedReciter {
                savedReciterId = reciter.id
            }
        }
    }
    
    @Published public private(set) var isLoading: Bool = true
    @AppStorage("selectedReciterId") private var savedReciterId: Int = 0
    
    public init(configuration: Configuration = .bundled) {
        loadReciters(with: configuration)
    }
    
    private func loadReciters(with config: Configuration) {
        self.isLoading = true
        switch config {
        case .bundled:
            loadAvailableRecitersSync()
        case .custom(let reciters):
            self.availableReciters = reciters.sorted { $0.id < $1.id }
            finalizeSelection()
        case .manifest(let url):
            Task { await loadFromExternalManifest(url: url) }
        }
    }

    private async func loadFromExternalManifest(url: URL) {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let entries = try JSONDecoder().decode([ReciterManifestEntry].self, from: data)
            var reciters: [ReciterInfo] = []
            for entry in entries {
                if let reciterTiming = AyahTimingService.shared.getReciter(id: entry.id) {
                    reciters.append(ReciterInfo(
                        id: reciterTiming.id,
                        nameArabic: reciterTiming.name,
                        nameEnglish: reciterTiming.name_en,
                        rewaya: reciterTiming.rewaya,
                        folderURL: reciterTiming.folder_url,
                        timingSource: ReciterDataProvider.timingSource(for: reciterTiming.id)
                    ))
                }
            }
            self.availableReciters = reciters.sorted { $0.id < $1.id }
            finalizeSelection()
        } catch {
            AppLogger.shared.error("Failed to load external manifest: \(error.localizedDescription)")
            loadAvailableRecitersSync()
        }
    }

    private func finalizeSelection() {
        if savedReciterId > 0, let saved = availableReciters.first(where: { $0.id == savedReciterId }) {
            self.selectedReciter = saved
        } else {
            self.selectedReciter = availableReciters.first
        }
        self.isLoading = false
    }
    
    // تأكد من وجود دالة loadAvailableRecitersSync الأصلية تحت هنا
}