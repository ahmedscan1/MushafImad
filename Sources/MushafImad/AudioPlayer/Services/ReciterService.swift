import Foundation
import SwiftUI
import Combine

/// Central registry that exposes available reciters and persists the selection.
/// Refactored to be fully modular and injectable.
@MainActor
public final class ReciterService: ObservableObject {
    
    // 1. إضافة خيارات التهيئة (Configuration)
    public enum Configuration {
        case bundled // المصدر الافتراضي
        case custom(reciters: [ReciterInfo]) // قائمة مخصصة جاهزة
        case manifest(url: URL) // رابط خارجي لملف JSON
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
    
    // 2. جعل الـ init عام (public) ويقبل Configuration
    public init(configuration: Configuration = .bundled) {
        loadReciters(with: configuration)
    }
    
    // MARK: - Logic Refactor
    
    private func loadReciters(with config: Configuration) {
        self.isLoading = true
        
        switch config {
        case .bundled:
            loadAvailableRecitersSync()
            
        case .custom(let reciters):
            self.availableReciters = reciters.sorted { $0.id < $1.id }
            finalizeSelection()
            
        case .manifest(let url):
            Task {
                await loadFromExternalManifest(url: url)
            }
        }
    }

    private async func loadFromExternalManifest(url: URL) {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let entries = try JSONDecoder().decode([ReciterManifestEntry].self, from: data)
            // تحويل الـ entries لـ ReciterInfo (بافتراض وجود خدمة AyahTimingService)
            var reciters: [ReciterInfo] = []
            for entry in entries {
                if let reciterTiming = AyahTimingService.shared.getReciter(id: entry.id) {
                    reciters.append(ReciterInfo(
                        id: reciterTiming.id,
                        nameArabic: reciterTiming.name,
                        nameEnglish: reciterTiming.name_en,
                        rewaya: reciterTiming.rewaya,
                        folderURL: reciterTiming.folder_url
                    ))
                }
            }
            self.availableReciters = reciters.sorted { $0.id < $1.id }
            finalizeSelection()
        } catch {
            AppLogger.shared.error("Failed to load external manifest: \(error.localizedDescription)")
            loadAvailableRecitersSync() // Fallback
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

    // ... (بقية الـ helper methods مثل loadReciterIdsFromManifest تظل كما هي لدعم الـ bundled config)
}
