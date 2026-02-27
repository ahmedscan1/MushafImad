import SwiftUI
import RealmSwift

public struct MushafView: View {
    @Binding var currentPage: Int
    
    // استخدام الـ Injection لضمان المرونة (ملاحظة الـ AI رقم 16-18)
    private let realmService: RealmService
    private let customReciterService: ReciterService?
    
    @EnvironmentObject private var reciterService: ReciterService
    @EnvironmentObject private var toastManager: ToastManager
    @StateObject private var viewModel = MushafViewModel()
    @StateObject private var playerViewModel = AudioPlayerViewModel()
    
    // الوصول للخدمة الفعالة سواء كانت محقونة أو من البيئة
    private var effectiveReciterService: ReciterService {
        customReciterService ?? reciterService
    }
    
    public init(
        page: Binding<Int>,
        realmService: RealmService = .shared,
        reciterService: ReciterService? = nil
    ) {
        self._currentPage = page
        self.realmService = realmService
        self.customReciterService = reciterService
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                renderContent(size: geometry.size)
            }
        }
        .onAppear {
            setupInitialState()
        }
        .onChange(of: currentPage) { _, newPage in
            if viewModel.scrollPosition != newPage {
                viewModel.scrollPosition = newPage
            }
        }
    }
    
    private func setupInitialState() {
        if viewModel.scrollPosition == nil {
            viewModel.scrollPosition = currentPage
        }
        
        // تحديث السورة بناءً على الصفحة باستخدام الـ realmService المحقون (ملاحظة رقم 93-96)
        let page = viewModel.scrollPosition ?? currentPage
        if let chapter = realmService.getChapterForPage(page) {
            viewModel.textModeInitialChapter = chapter.number
        }
    }
    
    @ViewBuilder
    private func renderContent(size: CGSize) -> some View {
        // ... (بقية كود الـ View)
        // ملاحظة: الـ AI طلب تحويل الـ if-let الطويل لـ guard-let لزيادة الوضوح
        EmptyView() // كود الـ UI يوضع هنا
    }
}

// التعديل في التعامل مع نهاية التلاوة (ملاحظة رقم 93-110)
extension MushafView {
    private func handleAudioFinished() {
        guard !effectiveReciterService.isLoading,
              let reciter = effectiveReciterService.selectedReciter,
              let _ = reciter.folderURL,
              let targetChapter = viewModel.nextChapter(from: playerViewModel.chapterNumber) else {
            return
        }
        
        withAnimation {
            viewModel.navigateToChapterAndPrepareScroll(targetChapter)
        }
        // ... تكملة إعداد المشغل
    }
}
