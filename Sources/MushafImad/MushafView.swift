import SwiftUI
import SwiftData

// ... (الإبقاء على Enums: ReadingTheme, DisplayMode, ScrollingMode كما هي بدون تغيير)

public struct MushafView: View {
    // 1. التعديل الأساسي: جعل الصفحة Binding للتحكم الخارجي
    @Binding public var currentPage: Int
    private let staticHighlightedVerse: Verse?
    private let highlightedVerseBinding: Binding<Verse?>?
    private let externalLongPressHandler: ((Verse) -> Void)?
    private let externalPageTapHandler: (() -> Void)?

    @State private var viewModel = ViewModel()
    @StateObject private var playerViewModel = QuranPlayerViewModel()
    
    // 2. السماح بحقن الـ Services بدلاً من الاعتماد الكلي على Environment
    private var customReciterService: ReciterService?
    
    @EnvironmentObject private var reciterService: ReciterService
    @EnvironmentObject private var toastManager: ToastManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var playingVerse: Verse? = nil

    @AppStorage("reading_theme") private var readingTheme: ReadingTheme = .white
    @AppStorage("scrolling_mode") private var scrollingMode: ScrollingMode = .horizontal
    @AppStorage("display_mode") private var displayMode: DisplayMode = .image
    @AppStorage("text_font_size") private var textFontSize: Double = 24.0
    @State private var textModeInitialChapter: Int = 1

    // 3. تحديث الـ Initializers ليكونوا Public ويدعموا الـ Binding
    public init(page: Binding<Int>,
                highlightedVerse: Verse? = nil,
                reciterService: ReciterService? = nil, // حقن اختياري
                onVerseLongPress: ((Verse) -> Void)? = nil,
                onPageTap: (() -> Void)? = nil
    ) {
        self._currentPage = page
        self.staticHighlightedVerse = highlightedVerse
        self.highlightedVerseBinding = nil
        self.customReciterService = reciterService
        self.externalLongPressHandler = onVerseLongPress
        self.externalPageTapHandler = onPageTap
    }

    public init(page: Binding<Int>,
                highlightedVerse: Binding<Verse?>,
                reciterService: ReciterService? = nil,
                onVerseLongPress: ((Verse) -> Void)? = nil,
                onPageTap: (() -> Void)? = nil
    ) {
        self._currentPage = page
        self.highlightedVerseBinding = highlightedVerse
        self.staticHighlightedVerse = nil
        self.customReciterService = reciterService
        self.externalLongPressHandler = onVerseLongPress
        self.externalPageTapHandler = onPageTap
    }

    public var body: some View {
        ZStack {
            readingTheme.color.ignoresSafeArea()
            if viewModel.isLoading || !viewModel.isInitialPageReady {
                LoadingView(message: viewModel.isLoading ? String(localized: "Loading Quran data...") : String(localized: "Preparing page..."))
            } else {
                pageView
                    .foregroundStyle(.naturalBlack)
            }
        }
        .environment(\.colorScheme, readingTheme == .night ? .dark : .light)
        .opacity(viewModel.contentOpacity)
        .onChange(of: viewModel.scrollPosition) { oldPage, newPage in
            guard let newPage = newPage else { return }
            // تحديث الـ Binding الخارجي عند التصفح الداخلي
            if currentPage != newPage {
                currentPage = newPage
            }
            Task {
                await viewModel.handlePageChange(from: oldPage, to: newPage)
            }
        }
        // الاستجابة للتغيير الخارجي في رقم الصفحة
        .onChange(of: currentPage) { _, newValue in
            if viewModel.scrollPosition != newValue {
                viewModel.scrollPosition = newValue
            }
        }
        .task {
            await viewModel.initializePageView(initialPage: currentPage)
        }
        .onAppear {
            if displayMode == .text {
                let page = viewModel.scrollPosition ?? currentPage
                textModeInitialChapter = RealmService.shared.getChapterForPage(page)?.number ?? 1
            }
        }
        // ... (بقية الـ toolbar والـ onChange الخاصة بالـ player تظل كما هي)
    }
    
    // ... (بقية الـ ViewBuilders: toolbarButtons, pageView, horizontalPageView, verticalPageView تظل كما هي)
}
