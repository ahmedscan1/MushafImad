import Foundation
import Combine

public final class ReciterService: ObservableObject {
    public enum Configuration {
        case bundled
        case custom(reciters: [ReciterInfo])
        case manifest(url: URL)
    }
    
    public static let shared = ReciterService()
    
    @Published public var availableReciters: [ReciterInfo] = []
    @Published public var selectedReciter: ReciterInfo?
    @Published public var isLoading: Bool = false
    
    private init() {
        loadReciters(with: .bundled)
    }
    
    public func loadReciters(with config: Configuration) {
        isLoading = true
        switch config {
        case .bundled:
            self.availableReciters = loadAvailableRecitersSync()
            finalizeSelection()
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
        // حماية الأمن: رفض الروابط غير المشفرة (HTTP)
        guard url.scheme?.lowercased() == "https" else {
            print("[ReciterService] Error: Only HTTPS is allowed for external manifests.")
            await MainActor.run {
                self.availableReciters = loadAvailableRecitersSync()
                finalizeSelection()
            }
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            let manifest = try decoder.decode(ReciterManifest.self, from: data)
            
            await MainActor.run {
                var reciters: [ReciterInfo] = []
                for entry in manifest.reciters {
                    // محاولة جلب بيانات القارئ من قاعدة التوقيت المحلية
                    if let timing = AyahTimingService.shared.getReciter(id: entry.id) {
                        reciters.append(ReciterInfo(
                            id: timing.id,
                            nameArabic: timing.name,
                            nameEnglish: timing.name_en,
                            rewaya: timing.rewaya,
                            folderURL: timing.folder_url
                        ))
                    }
                }
                
                // التأكد من أن القائمة ليست فارغة، وإلا نستخدم النسخة الاحتياطية
                if reciters.isEmpty {
                    self.availableReciters = loadAvailableRecitersSync()
                } else {
                    self.availableReciters = reciters.sorted { $0.id < $1.id }
                }
                finalizeSelection()
            }
        } catch {
            await MainActor.run {
                print("[ReciterService] Failed to load manifest: \(error)")
                self.availableReciters = loadAvailableRecitersSync()
                finalizeSelection()
            }
        }
    }
    
    // الدالة التي كانت مفقودة وتسببت في الاعتراض
    private func loadAvailableRecitersSync() -> [ReciterInfo] {
        guard let url = Bundle.mushafResources.url(forResource: "reciters", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(ReciterManifest.self, from: data) else {
            return [] // ارجاع قائمة فارغة كحماية أخيرة
        }
        
        return manifest.reciters.compactMap { entry in
            guard let timing = AyahTimingService.shared.getReciter(id: entry.id) else { return nil }
            return ReciterInfo(
                id: timing.id,
                nameArabic: timing.name,
                nameEnglish: timing.name_en,
                rewaya: timing.rewaya,
                folderURL: timing.folder_url
            )
        }.sorted { $0.id < $1.id }
    }
    
    private func finalizeSelection() {
        if selectedReciter == nil {
            selectedReciter = availableReciters.first
        }
        isLoading = false
    }
}

// هيكل البيانات المتوقع للمانيفست
struct ReciterManifest: Codable {
    struct Entry: Codable {
        let id: Int
    }
    let reciters: [Entry]
}
