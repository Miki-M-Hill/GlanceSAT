//
//  ExploreView.swift
//  GlanceSAT
//

import SwiftData
import SwiftUI

private struct LibraryScrollRequest: Equatable {
    let wordID: UUID
    let token: Int
}

/// Stable identity for `.task(id:)` so body recomposition does not restart the catalog fetch.
private struct LibraryCatalogTaskID: Equatable {
    let refreshToken: Int
    let searchText: String
    let status: LearningStatusFilter?
    let category: PassageDomain?
    let connotation: WordConnotationPolarity?
}

struct ExploreView: View {
    @Binding var pendingLibraryWordID: UUID?
    var isLibraryTabActive: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @EnvironmentObject private var paywallPresenter: PaywallPresenter
    @EnvironmentObject private var libraryFreemiumSession: LibraryFreemiumSession
    @FocusState private var isSearchFocused: Bool
    @AppStorage("hasPerformedFirstLibrarySwipe") private var hasPerformedFirstLibrarySwipe = false

    @State private var libraryViewModel = LibraryViewModel()
    @State private var showLibraryFilters = false
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var selectedStatus: LearningStatusFilter?
    @State private var selectedCategory: PassageDomain?
    @State private var selectedConnotation: WordConnotationPolarity?
    @State private var currentVisibleWordId: UUID?
    /// Reliable prior page for swipe counting (`currentVisibleWordId` onChange often reports `old` as nil).
    @State private var trackedScrollPosition: UUID?
    @State private var scrollRequest: LibraryScrollRequest?
    @State private var deepLinkScrollTask: Task<Void, Never>?
    @State private var appliedSearchText = ""
    @State private var libraryRefreshToken = 0
    @State private var needsLibraryRefresh = false

    init(
        pendingLibraryWordID: Binding<UUID?> = .constant(nil),
        isLibraryTabActive: Bool = true
    ) {
        _pendingLibraryWordID = pendingLibraryWordID
        self.isLibraryTabActive = isLibraryTabActive
    }

    private var hasActiveFilters: Bool {
        selectedStatus != nil || selectedCategory != nil || selectedConnotation != nil
    }

    private var currentCatalogFilter: LibraryCatalogFilter {
        LibraryCatalogFilter(
            searchText: appliedSearchText,
            status: selectedStatus,
            category: selectedCategory,
            connotation: selectedConnotation
        )
    }

    private var catalogTaskID: LibraryCatalogTaskID {
        LibraryCatalogTaskID(
            refreshToken: libraryRefreshToken,
            searchText: appliedSearchText,
            status: selectedStatus,
            category: selectedCategory,
            connotation: selectedConnotation
        )
    }

    @discardableResult
    private func prepareLibraryDeepLink(wordID: UUID) -> Bool {
        searchText = ""
        appliedSearchText = ""
        selectedStatus = nil
        selectedCategory = nil
        selectedConnotation = nil
        showLibraryFilters = false
        isSearchFocused = false

        libraryViewModel.prepareDeepLinkWord(id: wordID, modelContext: modelContext)
        guard libraryViewModel.word(for: wordID) != nil else { return false }

        currentVisibleWordId = wordID
        trackedScrollPosition = wordID
        libraryViewModel.rebuildIndex(filter: currentCatalogFilter)
        return true
    }

    private func rebuildLibraryIndex() {
        libraryViewModel.rebuildIndex(filter: currentCatalogFilter)
    }

    /// Marks the catalog stale after an external mutation (DB import, quiz SRS updates, etc.).
    private func markLibraryNeedsRefresh(clearWordCache: Bool = false) {
        if clearWordCache {
            libraryViewModel.clearWordCache()
        } else {
            libraryViewModel.ensureLexicalDataIsFresh()
        }
        needsLibraryRefresh = true
        if isLibraryTabActive {
            performLibraryRefreshIfNeeded()
        }
    }

    /// Runs a deferred catalog rebuild when the tab is visible and data was invalidated elsewhere.
    private func performLibraryRefreshIfNeeded() {
        guard needsLibraryRefresh else { return }
        needsLibraryRefresh = false
        libraryRefreshToken += 1
    }

    private func handleIndexRevisionChanged() {
        withAnimation(.easeOut(duration: 0.2)) {
            ensureLibraryScrollPositionIsValid()
        }

        if let focusID = currentVisibleWordId ?? libraryViewModel.orderedWordIDs.first {
            Task {
                await libraryViewModel.loadWord(id: focusID, modelContext: modelContext)
                await libraryViewModel.prefetchNeighbors(around: focusID, modelContext: modelContext)
            }
        }

        guard let wordID = pendingLibraryWordID ?? WidgetDeepLinkRouter.peekPendingWordID() else { return }
        scheduleLibraryDeepLink(wordID: wordID)
    }

    private func scrollLibraryToWord(_ wordID: UUID) {
        scrollRequest = LibraryScrollRequest(
            wordID: wordID,
            token: (scrollRequest?.token ?? 0) + 1
        )
    }

    private func ensureLibraryScrollPositionIsValid() {
        let ids = libraryViewModel.orderedWordIDs
        guard !ids.isEmpty else {
            currentVisibleWordId = nil
            trackedScrollPosition = nil
            return
        }
        if let visibleID = currentVisibleWordId, ids.contains(visibleID) {
            return
        }
        LibraryPagerDiagnostics.beginProgrammaticScroll("ensureLibraryScrollPositionIsValid")
        let target = ids.first
        let prior = currentVisibleWordId
        currentVisibleWordId = target
        applyLibraryScrollPositionChange(from: prior, to: target)
        LibraryPagerDiagnostics.endProgrammaticScroll("ensureLibraryScrollPositionIsValid")
    }

    private func resnapLibraryScrollPosition() {
        guard let current = currentVisibleWordId else { return }
        DispatchQueue.main.async {
            currentVisibleWordId = current
        }
    }

    private func finishLibraryDeepLink(wordID: UUID) {
        guard currentVisibleWordId == wordID else { return }
        pendingLibraryWordID = nil
        WidgetDeepLinkRouter.clearPendingWordID()
    }

    private func navigateLibraryPagerToWord(_ wordID: UUID) {
        guard libraryViewModel.orderedWordIDs.contains(wordID) else { return }

        LibraryPagerDiagnostics.beginProgrammaticScroll("navigateLibraryPagerToWord")
        let old = currentVisibleWordId
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            currentVisibleWordId = wordID
            trackedScrollPosition = wordID
        }

        DispatchQueue.main.async {
            currentVisibleWordId = wordID
            trackedScrollPosition = wordID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                currentVisibleWordId = wordID
                LibraryPagerDiagnostics.logScrollPositionChange(
                    old: old,
                    new: wordID,
                    orderedIDs: libraryViewModel.orderedWordIDs,
                    source: "navigateLibraryPagerToWord(async)"
                )
                LibraryPagerDiagnostics.endProgrammaticScroll("navigateLibraryPagerToWord")
            }
        }
    }

    private func retryPendingLibraryDeepLinkIfNeeded() {
        guard isLibraryTabActive else { return }
        guard let wordID = pendingLibraryWordID ?? WidgetDeepLinkRouter.peekPendingWordID() else { return }
        scheduleLibraryDeepLink(wordID: wordID)
    }

    private func applyLibraryScrollPositionChange(from systemOld: UUID?, to wordID: UUID?) {
        if wordID == trackedScrollPosition, wordID == currentVisibleWordId { return }

        let prior = trackedScrollPosition ?? systemOld

        if let wordID, let prior, prior != wordID, !hasPerformedFirstLibrarySwipe {
            hasPerformedFirstLibrarySwipe = true
            UserDefaults.standard.set(true, forKey: "hasPerformedFirstLibrarySwipe")
            NotificationCenter.default.post(name: .libraryFirstSwipePerformed, object: nil)
        }

        if !entitlementManager.hasPremiumAccess,
           libraryFreemiumSession.shouldBlockLibraryNavigation(
               wordIDs: libraryViewModel.orderedWordIDs,
               previous: prior,
               next: wordID
           ) {
            let revert = prior ?? libraryViewModel.orderedWordIDs.first
            LibraryPagerDiagnostics.beginProgrammaticScroll("freemiumRevert")
            currentVisibleWordId = revert
            trackedScrollPosition = revert
            LibraryPagerDiagnostics.endProgrammaticScroll("freemiumRevert")
            AnalyticsManager.trackDailyLimitHit(source: "library_swipe", limitType: "library_pager")
            paywallPresenter.presentPaywall(source: "library_swipe", onDismissed: {
                NotificationCenter.default.post(name: .libraryFreemiumPaywallDismissed, object: nil)
            })
            return
        }

        // Do not write `currentVisibleWordId` on user swipes — paging already settled; rewriting it causes a post-land nudge that drifts upward each swipe.
        if let wordID {
            trackedScrollPosition = wordID
            libraryViewModel.loadMoreIfNeeded(near: wordID, modelContext: modelContext)
            Task {
                await libraryViewModel.loadWord(id: wordID, modelContext: modelContext)
                await libraryViewModel.prefetchNeighbors(around: wordID, modelContext: modelContext)
            }
        } else {
            trackedScrollPosition = nil
        }
    }

    private func scheduleLibraryDeepLink(wordID: UUID) {
        deepLinkScrollTask?.cancel()
        deepLinkScrollTask = Task { @MainActor in
            for attempt in 0 ..< 30 {
                if Task.isCancelled { return }
                guard prepareLibraryDeepLink(wordID: wordID) else {
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    continue
                }

                scrollLibraryToWord(wordID)
                try? await Task.sleep(nanoseconds: 150_000_000)
                scrollLibraryToWord(wordID)
                try? await Task.sleep(nanoseconds: 200_000_000)

                if currentVisibleWordId == wordID {
                    finishLibraryDeepLink(wordID: wordID)
                    return
                }

                try? await Task.sleep(nanoseconds: UInt64(80_000_000 + (attempt * 40_000_000)))
            }
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    libraryHeader(safeAreaTop: proxy.safeAreaInsets.top)

                    if libraryViewModel.isLoadingIndex, libraryViewModel.orderedWordIDs.isEmpty {
                        libraryLoadingPlaceholder
                    } else if libraryViewModel.orderedWordIDs.isEmpty {
                        Spacer(minLength: 0)
                        emptyState
                            .padding(.horizontal, 20)
                        Spacer(minLength: 0)
                    } else {
                        LibraryWordPager(
                            wordIDs: libraryViewModel.orderedWordIDs,
                            viewModel: libraryViewModel,
                            currentVisibleWordId: $currentVisibleWordId,
                            scrollRequest: $scrollRequest,
                            onNavigateToWord: navigateLibraryPagerToWord,
                            onActivePageChanged: { prior, newID in
                                applyLibraryScrollPositionChange(from: prior, to: newID)
                            },
                            onResnapScrollPosition: resnapLibraryScrollPosition
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            if trackedScrollPosition == nil {
                                trackedScrollPosition = currentVisibleWordId ?? libraryViewModel.orderedWordIDs.first
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(HubPalette.linen)
            .simultaneousGesture(
                TapGesture().onEnded {
                    isSearchFocused = false
                    GlanceKeyboard.dismiss()
                }
            )
            .task(id: searchText) {
                try? await Task.sleep(nanoseconds: 320_000_000)
                guard !Task.isCancelled else { return }
                appliedSearchText = searchText
            }
            .task(id: catalogTaskID) {
                libraryViewModel.configure(container: modelContext.container)
                libraryViewModel.rebuildIndex(filter: currentCatalogFilter)
            }
            .onChange(of: libraryViewModel.orderedWordIDs.count) { oldCount, newCount in
                guard LibraryPagerDiagnostics.isEnabled, oldCount != newCount else { return }
                LibraryPagerDiagnostics.auditOrderedWordIDs(
                    libraryViewModel.orderedWordIDs,
                    label: "orderedWordIDs.count \(oldCount)→\(newCount)",
                    modelContext: modelContext
                )
            }
            .onAppear {
                retryPendingLibraryDeepLinkIfNeeded()
            }
            .onChange(of: pendingLibraryWordID, initial: true) { _, wordID in
                guard let wordID else { return }
                libraryViewModel.prepareDeepLinkWord(id: wordID, modelContext: modelContext)
                currentVisibleWordId = wordID
                trackedScrollPosition = wordID
                scheduleLibraryDeepLink(wordID: wordID)
            }
            .onChange(of: libraryViewModel.indexRevision) { oldRevision, newRevision in
                LibraryPagerDiagnostics.log(
                    "indexRevision \(oldRevision)→\(newRevision) scrollID=\(currentVisibleWordId?.uuidString ?? "nil")"
                )
                handleIndexRevisionChanged()
            }
            .onChange(of: isLibraryTabActive, initial: true) { _, isActive in
                guard isActive else { return }
                AnalyticsManager.trackLibraryViewed()
                libraryViewModel.ensureLexicalDataIsFresh()
                performLibraryRefreshIfNeeded()
                resnapLibraryScrollPosition()
                retryPendingLibraryDeepLinkIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .wordDatabaseDidChange)) { _ in
                markLibraryNeedsRefresh(clearWordCache: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .insightsWordStatsDidUpdate)) { _ in
                markLibraryNeedsRefresh(clearWordCache: true)
            }
            .glanceNavigationBarChrome(colorScheme: colorScheme, isHidden: true)
        }
        .sheet(isPresented: $showLibraryFilters) {
            LibraryFiltersSheet(
                selectedStatus: $selectedStatus,
                selectedCategory: $selectedCategory,
                selectedConnotation: $selectedConnotation
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(entitlementManager)
                .environmentObject(paywallPresenter)
        }
    }

    private func libraryHeaderTopInset(safeAreaTop: CGFloat) -> CGFloat {
        let screenHeight = GlanceDeviceLayout.screenHeight
        let inset = GlanceDeviceLayout.heightFraction(0.012, in: screenHeight)
            + max(safeAreaTop - GlanceDeviceLayout.proportional(5, in: screenHeight), 0)
        return inset * 0.5
    }

    private func libraryHeader(safeAreaTop: CGFloat) -> some View {
        let headerTop = libraryHeaderTopInset(safeAreaTop: safeAreaTop)
        let headerBottom = GlanceDeviceLayout.proportional(8, in: GlanceDeviceLayout.screenHeight)
        let headerHorizontal = GlanceDeviceLayout.proportional(20, in: GlanceDeviceLayout.screenHeight)

        return VStack(spacing: GlanceDeviceLayout.proportional(10, in: GlanceDeviceLayout.screenHeight)) {
            topControls

            if hasActiveFilters {
                libraryActiveFilterChips
            }
        }
        .padding(.horizontal, headerHorizontal)
        .padding(.top, headerTop)
        .padding(.bottom, headerBottom)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: hasActiveFilters)
    }

    private var libraryActiveFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let selectedStatus {
                    LibraryFilterChip(title: selectedStatus.label) {
                        self.selectedStatus = nil
                    }
                }
                if let selectedCategory {
                    LibraryFilterChip(title: selectedCategory.displayTitle) {
                        self.selectedCategory = nil
                    }
                }
                if let selectedConnotation {
                    LibraryFilterChip(title: selectedConnotation.label) {
                        self.selectedConnotation = nil
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var topControls: some View {
        HStack {
            IconCircleButton(
                systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease",
                isActive: hasActiveFilters
            ) {
                showLibraryFilters = true
            }
            .accessibilityLabel("Filters")

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(GlanceHubFont.regular(15))
                    .foregroundStyle(HubPalette.espressoMuted)

                TextField("Search vocabulary", text: $searchText)
                    .font(GlanceHubFont.regular(15))
                    .foregroundStyle(HubPalette.espresso)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(HubPalette.oatmealDeep.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.42), lineWidth: 0.7)
                    )
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            IconCircleButton(systemName: "gearshape") {
                showSettings = true
            }
            .accessibilityLabel("Settings")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(HubPalette.espressoMuted)
            Text("No matching words")
                .font(GlanceHubFont.semibold(20))
                .foregroundStyle(HubPalette.espresso)
            Text("Adjust your filters or search query.")
                .font(GlanceHubFont.regular(15))
                .foregroundStyle(HubPalette.espressoMuted)
        }
        .padding(28)
    }

    private var libraryLoadingPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            libraryWordLoadingPlaceholder(maxHeight: 420)
                .padding(.horizontal, 20)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func libraryWordLoadingPlaceholder(maxHeight: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 14) {
        Text("Placeholder headword")
            .font(GlanceHubFont.semibold(28))
        Text("Placeholder definition line for loading state")
            .font(GlanceHubFont.regular(16))
        Text("Another placeholder definition line")
            .font(GlanceHubFont.regular(16))
    }
    .foregroundStyle(HubPalette.espresso)
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
        HubSolidCardChrome.background()
    }
    .frame(maxHeight: maxHeight, alignment: .center)
    .redacted(reason: .placeholder)
}

private func libraryWordFailedPlaceholder(maxHeight: CGFloat, onRetry: @escaping () -> Void) -> some View {
    VStack(spacing: 16) {
        Text("Failed to load")
            .font(GlanceHubFont.medium(17))
            .foregroundStyle(HubPalette.espressoMuted)
        Button(action: onRetry) {
            Label("Retry", systemImage: "arrow.clockwise")
                .font(GlanceHubFont.medium(15))
        }
        .buttonStyle(.bordered)
        .tint(HubPalette.plantDeep)
    }
    .frame(maxWidth: .infinity)
    .padding(24)
    .background {
        HubSolidCardChrome.background()
    }
    .frame(maxHeight: maxHeight, alignment: .center)
}

/// TikTok-style vertical paging: one swipe always moves exactly one word.
private struct LibraryWordPager: View {
    let wordIDs: [UUID]
    @Bindable var viewModel: LibraryViewModel
    @Binding var currentVisibleWordId: UUID?
    @Binding var scrollRequest: LibraryScrollRequest?
    let onNavigateToWord: (UUID) -> Void
    let onActivePageChanged: (UUID?, UUID?) -> Void
    let onResnapScrollPosition: () -> Void

    @State private var settledPrimaryPageID: UUID?
    @State private var visibilitySettlementTask: Task<Void, Never>?

    private var renderPageCells: [(offset: Int, id: UUID)] {
        let cells = wordIDs.enumerated().map { (offset: $0.offset, id: $0.element) }
        if LibraryPagerDiagnostics.useStandardVStack {
            return Array(cells.prefix(LibraryPagerDiagnostics.vStackTestMaxCells))
        }
        return cells
    }

    @ViewBuilder
    private func libraryPageCells(
        _ cells: [(offset: Int, id: UUID)],
        pageWidth: CGFloat,
        pageHeight: CGFloat
    ) -> some View {
        ForEach(cells, id: \.id) { index, wordID in
            LibraryWordPageContainer(
                wordID: wordID,
                viewModel: viewModel,
                catalogIndex: index
            )
            .frame(width: pageWidth, height: pageHeight)
            .id(wordID)
            .reportsLibraryPageVisibility(wordID: wordID)
        }
    }

    private func settlePrimaryPage(from pageOffsets: [UUID: CGFloat], viewportHeight: CGFloat) {
        guard let newID = LibraryPagerActivePageResolver.primaryPageID(
            in: pageOffsets,
            viewportHeight: viewportHeight
        ) else { return }
        guard newID != settledPrimaryPageID else { return }

        let prior = settledPrimaryPageID
        settledPrimaryPageID = newID

        guard !LibraryPagerDiagnostics.isProgrammaticScroll else { return }
        onActivePageChanged(prior, newID)
    }

    var body: some View {
        GeometryReader { proxy in
            let pageHeight = proxy.size.height
            let pageWidth = proxy.size.width
            let cells = renderPageCells

            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    if LibraryPagerDiagnostics.useStandardVStack {
                        VStack(spacing: 0) {
                            libraryPageCells(cells, pageWidth: pageWidth, pageHeight: pageHeight)
                        }
                        .scrollTargetLayout()
                    } else {
                        LazyVStack(spacing: 0) {
                            libraryPageCells(cells, pageWidth: pageWidth, pageHeight: pageHeight)
                        }
                        .scrollTargetLayout()
                    }
                }
            }
            .frame(width: pageWidth, height: pageHeight)
            .coordinateSpace(name: LibraryPagerCoordinateSpace.scroll)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentVisibleWordId, anchor: .center)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .onAppear {
                LibraryPagerDiagnostics.logViewport(
                    scrollFrame: proxy.size,
                    safeArea: proxy.safeAreaInsets,
                    headerHeight: 0,
                    listRenderRevision: viewModel.indexRevision
                )
                if settledPrimaryPageID == nil {
                    settledPrimaryPageID = currentVisibleWordId ?? wordIDs.first
                }
                onResnapScrollPosition()
            }
            .onChange(of: proxy.size) { _, size in
                LibraryPagerDiagnostics.logViewport(
                    scrollFrame: size,
                    safeArea: proxy.safeAreaInsets,
                    headerHeight: 0,
                    listRenderRevision: viewModel.indexRevision
                )
            }
            .onPreferenceChange(LibraryPageVisibilityPreference.self) { pageOffsets in
                visibilitySettlementTask?.cancel()
                visibilitySettlementTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    guard !Task.isCancelled else { return }
                    settlePrimaryPage(from: pageOffsets, viewportHeight: pageHeight)
                }
            }
            .onChange(of: currentVisibleWordId) { _, newID in
                guard let newID, newID != settledPrimaryPageID else { return }
                let prior = settledPrimaryPageID
                settledPrimaryPageID = newID
                guard !LibraryPagerDiagnostics.isProgrammaticScroll else { return }
                onActivePageChanged(prior, newID)
            }
            .onChange(of: scrollRequest) { _, request in
                guard let request else { return }
                onNavigateToWord(request.wordID)
            }
        }
        .ignoresSafeArea()
    }
}

private struct LibraryWordPageContainer: View {
    let wordID: UUID
    @Bindable var viewModel: LibraryViewModel
    var catalogIndex: Int = -1
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom
            let pageHeight = proxy.size.height
            let horizontalInset = LibraryLayoutMetrics.pageHorizontalInset(for: pageHeight)
            let verticalInset = LibraryLayoutMetrics.pageVerticalInset(for: pageHeight)
            let tabBarClearance = LibraryLayoutMetrics.bottomTabBarClearance(for: pageHeight)
            let cardMaxHeight = max(
                0,
                pageHeight
                    - (verticalInset * 2)
                    - tabBarClearance
                    - safeTop
                    - safeBottom
            )

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Group {
                    if let word = viewModel.word(for: wordID) {
                        ExploreWordPageCard(word: word, maxContentHeight: cardMaxHeight)
                    } else if viewModel.wordLoadState(for: wordID) == .failed {
                        libraryWordFailedPlaceholder(maxHeight: cardMaxHeight) {
                            Task {
                                await viewModel.retryLoadWord(id: wordID, modelContext: modelContext)
                            }
                        }
                    } else {
                        libraryWordLoadingPlaceholder(maxHeight: cardMaxHeight)
                    }
                }
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: cardMaxHeight, alignment: .center)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, horizontalInset)
            .padding(.top, safeTop)
            .padding(.bottom, tabBarClearance + safeBottom)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .clipped()
        .task(id: wordID) {
            await viewModel.loadWord(id: wordID, modelContext: modelContext)
        }
        .onAppear {
            LibraryPagerDiagnostics.logCellAppear(
                wordID: wordID,
                index: catalogIndex,
                headword: viewModel.word(for: wordID)?.word,
                orderedCount: viewModel.orderedWordIDs.count
            )
            viewModel.loadMoreIfNeeded(near: wordID, modelContext: modelContext)
        }
        .onDisappear {
            LibraryPagerDiagnostics.logCellDisappear(wordID: wordID, index: catalogIndex)
        }
    }
}

private struct ExploreWordPageCard: View {
    let word: Word
    let maxContentHeight: CGFloat
    @State private var sensePage = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var originOrHookBody: String? {
        word.cardOriginOrHookBody
    }

    private var originOrHookTitle: String {
        word.cardOriginOrHookTitle
    }

    var body: some View {
        let senses = word.displaySenseBlocks
        let active = senses[safe: sensePage] ?? senses.first
        let card = cardBody(senses: senses, active: active)

        Group {
            if usesAccessibilityLayout {
                ScrollView(.vertical, showsIndicators: false) {
                    card
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            } else {
                card
            }
        }
        .frame(maxWidth: .infinity, maxHeight: maxContentHeight, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.22), value: sensePage)
        .background {
            HubSolidCardChrome.background()
        }
        .onChange(of: word.id) { _, _ in
            sensePage = 0
        }
    }

    @ViewBuilder
    private func cardBody(
        senses: [WordSenseBlock],
        active: WordSenseBlock?
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Group {
                        if usesAccessibilityLayout {
                            Text(word.word)
                                .lineLimit(nil)
                        } else {
                            Text(word.word)
                                .lineLimit(2)
                        }
                    }
                    .font(GlanceHubFont.semibold(34))
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(HubPalette.espresso)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if senses.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(Array(senses.enumerated()), id: \.offset) { index, sense in
                            Button {
                                GlanceHaptics.light()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                    sensePage = index
                                }
                            } label: {
                                partOfSpeechChip(sense.partOfSpeech, isSelected: index == sensePage)
                            }
                            .buttonStyle(.plain)
                        }

                        WordConnotationRow(word: word, compact: true)
                            .layoutPriority(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.top, 12)
                } else if let only = senses.first {
                    HStack(alignment: .center, spacing: 6) {
                        partOfSpeechChip(only.partOfSpeech, isSelected: true)
                        WordConnotationRow(word: word, compact: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 12)
                }

                Divider()
                    .background(HubPalette.espressoFaint)
                    .padding(.vertical, 12)

                if let active {
                    Text("Definition")
                        .font(GlanceHubFont.semibold(12))
                        .tracking(0.6)
                        .foregroundStyle(HubPalette.plantDeep)

                    definitionText(active.definition)
                        .padding(.top, 6)

                    Text("Example")
                        .font(GlanceHubFont.semibold(12))
                        .tracking(0.6)
                        .foregroundStyle(HubPalette.plantDeep)
                        .padding(.top, 14)

                    bodyText(active.exampleSentence, italic: true)
                        .padding(.top, 6)
                }

                if GlanceProductSurface.showsWordEtymologyAndHooks, let body = originOrHookBody {
                    Text(originOrHookTitle)
                        .font(GlanceHubFont.semibold(12))
                        .tracking(0.6)
                        .foregroundStyle(HubPalette.plantDeep)
                        .padding(.top, 14)

                    bodyText(body, italic: false)
                        .lineSpacing(3)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)
        }
        .padding(22)
    }

    @ViewBuilder
    private func definitionText(_ text: String) -> some View {
        if usesAccessibilityLayout {
            Text(text)
                .font(GlanceHubFont.medium(19))
                .foregroundStyle(HubPalette.espresso)
                .lineLimit(nil)
        } else {
            Text(text)
                .font(GlanceHubFont.medium(19))
                .foregroundStyle(HubPalette.espresso)
        }
    }

    @ViewBuilder
    private func bodyText(_ text: String, italic: Bool) -> some View {
        if usesAccessibilityLayout {
            Text(text)
                .font(GlanceHubFont.regular(18))
                .italic(italic)
                .foregroundStyle(HubPalette.espresso)
                .lineLimit(nil)
        } else {
            Text(text)
                .font(GlanceHubFont.regular(18))
                .italic(italic)
                .foregroundStyle(HubPalette.espresso)
        }
    }

    private func partOfSpeechChip(_ label: String, isSelected: Bool) -> some View {
        Text(label)
            .font(GlanceHubFont.semibold(12))
            .foregroundStyle(isSelected ? WordCardChrome.partOfSpeechForeground : WordCardChrome.partOfSpeechInactiveForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? WordCardChrome.partOfSpeechFill : WordCardChrome.partOfSpeechInactiveFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.white.opacity(0.35) : WordCardChrome.partOfSpeechInactiveStroke,
                                lineWidth: isSelected ? 1 : 0.7
                            )
                    )
            )
    }
}

// MARK: - Library filters

private struct LibraryFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedStatus: LearningStatusFilter?
    @Binding var selectedCategory: PassageDomain?
    @Binding var selectedConnotation: WordConnotationPolarity?

    private var hasActiveFilters: Bool {
        selectedStatus != nil || selectedCategory != nil || selectedConnotation != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    libraryFilterSectionHeader("Learning")
                    libraryFilterCard {
                        libraryFilterRow(
                            icon: "books.vertical",
                            title: "Any status",
                            subtitle: "Show the full library",
                            isSelected: selectedStatus == nil
                        ) {
                            selectedStatus = nil
                        }
                        libraryFilterRowDivider
                        ForEach(Array(LearningStatusFilter.allCases.enumerated()), id: \.element.id) { index, status in
                            if index > 0 { libraryFilterRowDivider }
                            libraryFilterRow(
                                icon: status.filterIcon,
                                title: status.label,
                                subtitle: status.filterSubtitle,
                                isSelected: selectedStatus == status
                            ) {
                                selectedStatus = status
                            }
                        }
                    }

                    libraryFilterSectionHeader("Passage")
                    libraryFilterCard {
                        libraryFilterRow(
                            icon: "text.book.closed",
                            title: "Any passage",
                            subtitle: "All SAT passage themes",
                            isSelected: selectedCategory == nil
                        ) {
                            selectedCategory = nil
                        }
                        libraryFilterRowDivider
                        ForEach(Array(PassageDomain.displayOrder.enumerated()), id: \.element.id) { index, domain in
                            if index > 0 { libraryFilterRowDivider }
                            libraryFilterRow(
                                icon: domain.filterIcon,
                                title: domain.displayTitle,
                                subtitle: domain.filterSubtitle,
                                isSelected: selectedCategory == domain
                            ) {
                                selectedCategory = domain
                            }
                        }
                    }

                    libraryFilterSectionHeader("Connotation")
                    libraryFilterCard {
                        libraryFilterRow(
                            icon: "slider.horizontal.3",
                            title: "Any charge",
                            subtitle: "Positive, negative, neutral, or mixed",
                            isSelected: selectedConnotation == nil
                        ) {
                            selectedConnotation = nil
                        }
                        libraryFilterRowDivider
                        ForEach(Array(WordConnotationPolarity.filterOptions.enumerated()), id: \.element) { index, polarity in
                            if index > 0 { libraryFilterRowDivider }
                            libraryFilterRow(
                                icon: polarity.filterIcon,
                                title: polarity.label,
                                subtitle: polarity.filterSubtitle,
                                isSelected: selectedConnotation == polarity
                            ) {
                                selectedConnotation = polarity
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(HubPalette.linen.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .glanceNavigationBarChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DailyQuizBackButton(accessibilityLabel: "Close filters") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Filters")
                        .font(GlanceHubFont.semibold(17))
                        .foregroundStyle(HubPalette.espresso)
                        .frame(height: 44)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    DailyQuizToolbarIconButton(
                        systemName: "arrow.counterclockwise",
                        accessibilityLabel: "Reset filters",
                        isEnabled: hasActiveFilters
                    ) {
                        resetFilters()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .presentationBackground(HubPalette.linen)
    }

    private func libraryFilterSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(2)
            .foregroundStyle(HubPalette.espressoMuted)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }

    private func libraryFilterCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(HubPalette.oatmeal.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HubPalette.espresso.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: HubPalette.espresso.opacity(0.05), radius: 14, y: 8)
    }

    private var libraryFilterRowDivider: some View {
        Rectangle()
            .fill(HubPalette.espresso.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 54)
    }

    private func libraryFilterRow(
        icon: String,
        title: String,
        subtitle: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(isSelected ? HubPalette.plantDeep : HubPalette.espresso)
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 26, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(HubPalette.espresso)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(HubPalette.espressoMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? HubPalette.plantDeep : HubPalette.espressoFaint.opacity(0.55))
                    .symbolRenderingMode(.monochrome)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func resetFilters() {
        selectedStatus = nil
        selectedCategory = nil
        selectedConnotation = nil
    }
}

private extension LearningStatusFilter {
    var filterIcon: String {
        switch self {
        case .unseen: return "eye"
        case .learning: return "arrow.triangle.2.circlepath"
        case .mastered: return "checkmark.seal"
        }
    }

    var filterSubtitle: String {
        switch self {
        case .unseen: return "Not yet in your rotation"
        case .learning: return "Due for review or in progress"
        case .mastered: return "Words you have learned"
        }
    }
}

private extension WordConnotationPolarity {
    var filterIcon: String {
        switch self {
        case .positive: return "plus.circle"
        case .negative: return "minus.circle"
        case .neutral: return "equal.circle"
        case .mixed: return "arrow.left.arrow.right"
        }
    }

    var filterSubtitle: String {
        switch self {
        case .positive: return "Favorable or uplifting tone"
        case .negative: return "Critical or unfavorable tone"
        case .neutral: return "Descriptive, without strong charge"
        case .mixed: return "Shifts tone within the word"
        }
    }
}

private struct LibraryFilterChip: View {
    let title: String
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 5) {
                Text(title)
                    .font(GlanceHubFont.medium(13))
                    .foregroundStyle(HubPalette.espresso)
                    .lineLimit(1)

                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HubPalette.espressoMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(HubPalette.plantDeep.opacity(0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(HubPalette.plantDeep.opacity(0.22), lineWidth: 0.7)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(title) filter")
    }
}

private struct IconCircleButton: View {
    let systemName: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(GlanceHubFont.semibold(16))
                .foregroundStyle(isActive ? HubPalette.plantDeep : HubPalette.espresso)
                .frame(width: 42, height: 42)
                .background {
                    GlanceAdaptiveGlassCircle(
                        diameter: 42,
                        activeTint: isActive ? HubPalette.plantDeep.opacity(0.14) : nil
                    )
                }
                .overlay(
                    Circle()
                        .strokeBorder(
                            isActive ? HubPalette.plantDeep.opacity(0.35) : Color.white.opacity(0.58),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private extension WordConnotationPolarity {
    static let filterOptions: [WordConnotationPolarity] = [.positive, .negative, .neutral, .mixed]
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("Explore") {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Word.self, configurations: configuration)
    let context = container.mainContext

    let sample = Word(
        id: UUID(),
        word: "Canvas",
        partOfSpeech: "noun",
        definition: "A piece of cloth used as a painting surface.",
        exampleSentence: "The artist stretched the canvas before beginning.",
        etymology: "From Old North French canevaz, from Latin cannabis.",
        synonyms: ["fabric", "surface"],
        sensesJSON: """
        [{"partOfSpeech":"noun","definition":"A piece of cloth used as a painting surface.","synonyms":["fabric","surface"],"exampleSentence":"The artist stretched the canvas before beginning."},{"partOfSpeech":"verb","definition":"To inspect closely or ask many people for information.","synonyms":["survey","question"],"exampleSentence":"They canvassed the district before election day."}]
        """,
        difficulty: 2,
        frequencyRank: 5,
        category: "literature",
        nextReviewDate: Date()
    )
    context.insert(sample)
    try? context.save()

    return ExploreView()
        .modelContainer(container)
}
