import SwiftUI
import SwiftData

public struct MushafView: View {
    // 1. التعديل الأساسي: دعم التحكم الخارجي عبر Binding
    @Binding public var currentPage: Int
    private let staticHighlightedVerse: Verse?
    private let highlightedVerseBinding: Binding<Verse?>?
    private let externalLongPressHandler: ((Verse) -> Void)?
    private let externalPageTapHandler: (() -> Void)?

    @State private var viewModel = ViewModel()
    @StateObject private var playerViewModel = QuranPlayerViewModel()
    
    // دعم حقن الـ Services
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

    // 2. تحديث الـ Initializers ليكونوا Public ويدعموا الـ Binding
    public init(page: Binding<Int>,
                highlightedVerse: Verse? = nil,
                reciterService: ReciterService? = nil,
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
            // تحديث الـ Binding الخارجي عند التصفح
            if currentPage != newPage {
                currentPage = newPage
            }
            Task { await viewModel.handlePageChange(from: oldPage, to: newPage) }
        }
        .onChange(of: currentPage) { _, newValue in
            if viewModel.scrollPosition != newValue {
                viewModel.scrollPosition = newValue
            }
        }
        .task { await viewModel.initializePageView(initialPage: currentPage) }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                toolbarButtons
            }
        }
        // دمج منطق الـ Player الجديد من نسخة Main
        .onChange(of: playerViewModel.playbackState) { oldState, newState in
            switch newState {
            case .idle: playingVerse = nil
            case .finished:
                if !reciterService.isLoading,
                   let reciter = reciterService.selectedReciter,
                   let baseURL = reciter.audioBaseURL,
                   let target = viewModel.nextChapter(from: playerViewModel.chapterNumber) {
                    withAnimation { viewModel.navigateToChapterAndPrepareScroll(target) }
                    playerViewModel.configureIfNeeded(
                        baseURL: baseURL,
                        chapterNumber: target.number,
                        chapterName: target.displayTitle,
                        reciterName: reciter.displayName,
                        reciterId: reciter.id,
                        timingSource: reciter.timingSource
                    )
                    playerViewModel.startIfNeeded(autoPlay: true)
                }
            default: break
            }
        }
    }

    // ... يتم الإبقاء على ViewBuilders (toolbarButtons, pageView) كما هي في نسختك الأصلية
}