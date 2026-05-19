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

struct ExploreView: View {
    @Binding var pendingLibraryWordID: UUID?
    var isLibraryTabActive: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Word.word, order: .forward) private var allWords: [Word]
    @FocusState private var isSearchFocused: Bool

    @State private var showLibraryFilters = false
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var selectedStatus: LearningStatusFilter?
    @State private var selectedCategory: PassageDomain?
    @State private var selectedConnotation: WordConnotationPolarity?
    @State private var scrollPosition: UUID?
    @State private var scrollRequest: LibraryScrollRequest?
    @State private var deepLinkScrollTask: Task<Void, Never>?

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

    @discardableResult
    private func prepareLibraryDeepLink(wordID: UUID) -> Bool {
        searchText = ""
        selectedStatus = nil
        selectedCategory = nil
        selectedConnotation = nil
        showLibraryFilters = false
        isSearchFocused = false

        guard allWords.contains(where: { $0.id == wordID }) else { return false }
        guard filteredWords.contains(where: { $0.id == wordID }) else { return false }
        return true
    }

    private func scrollLibraryToWord(_ wordID: UUID) {
        scrollRequest = LibraryScrollRequest(
            wordID: wordID,
            token: (scrollRequest?.token ?? 0) + 1
        )
    }

    private func ensureLibraryScrollPositionIsValid() {
        guard !filteredWords.isEmpty else {
            scrollPosition = nil
            return
        }
        if let scrollPosition,
           filteredWords.contains(where: { $0.id == scrollPosition }) {
            return
        }
        scrollPosition = filteredWords.first?.id
    }

    private func finishLibraryDeepLink(wordID: UUID) {
        guard scrollPosition == wordID else { return }
        pendingLibraryWordID = nil
        WidgetDeepLinkRouter.clearPendingWordID()
    }

    private func navigateLibraryPagerToWord(_ wordID: UUID) {
        guard filteredWords.contains(where: { $0.id == wordID }) else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollPosition = wordID
        }

        DispatchQueue.main.async {
            scrollPosition = wordID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                scrollPosition = wordID
            }
        }
    }

    private func retryPendingLibraryDeepLinkIfNeeded() {
        guard isLibraryTabActive else { return }
        guard let wordID = pendingLibraryWordID ?? WidgetDeepLinkRouter.peekPendingWordID() else { return }
        scheduleLibraryDeepLink(wordID: wordID)
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

                if scrollPosition == wordID {
                    finishLibraryDeepLink(wordID: wordID)
                    return
                }

                try? await Task.sleep(nanoseconds: UInt64(80_000_000 + (attempt * 40_000_000)))
            }
        }
    }

    private var filteredWords: [Word] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allWords.filter { word in
            if let selectedStatus, LearningStatusFilter.from(word.status) != selectedStatus { return false }
            if let selectedCategory, word.resolvedPassageDomain != selectedCategory { return false }
            if let selectedConnotation, WordConnotationPolarity(raw: word.semanticCharge) != selectedConnotation {
                return false
            }

            if query.isEmpty { return true }
            if word.word.lowercased().contains(query) { return true }
            if word.category.lowercased().contains(query) { return true }
            if word.resolvedPassageDomain.displayTitle.lowercased().contains(query) { return true }
            if let ety = word.etymology?.lowercased(), ety.contains(query) { return true }
            if let hook = word.memoryHookText?.lowercased(), hook.contains(query) { return true }
            return word.displaySenseBlocks.contains { sense in
                sense.partOfSpeech.lowercased().contains(query)
                    || sense.definition.lowercased().contains(query)
                    || sense.exampleSentence.lowercased().contains(query)
            }
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    libraryHeader

                    if filteredWords.isEmpty {
                        Spacer(minLength: 0)
                        emptyState
                            .padding(.horizontal, 20)
                        Spacer(minLength: 0)
                    } else {
                        GeometryReader { cardProxy in
                            let pageHeight = max(1, cardProxy.size.height)

                            LibraryWordPager(
                                words: filteredWords,
                                pageHeight: pageHeight,
                                scrollPosition: $scrollPosition,
                                scrollRequest: $scrollRequest,
                                onNavigateToWord: navigateLibraryPagerToWord
                            )
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .background(HubPalette.linen)
            .onChange(of: pendingLibraryWordID, initial: true) { _, wordID in
                guard let wordID else { return }
                scheduleLibraryDeepLink(wordID: wordID)
            }
            .onChange(of: allWords.count) { _, _ in
                ensureLibraryScrollPositionIsValid()
                guard let wordID = pendingLibraryWordID ?? WidgetDeepLinkRouter.peekPendingWordID() else { return }
                scheduleLibraryDeepLink(wordID: wordID)
            }
            .onChange(of: filteredWords.map(\.id)) { _, _ in
                ensureLibraryScrollPositionIsValid()
            }
            .onAppear {
                ensureLibraryScrollPositionIsValid()
                retryPendingLibraryDeepLinkIfNeeded()
            }
            .onChange(of: isLibraryTabActive) { _, isActive in
                guard isActive else { return }
                retryPendingLibraryDeepLinkIfNeeded()
            }
            .navigationTitle("Glance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(HubPalette.linen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .tint(HubPalette.espresso)
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
        }
    }

    private var libraryHeader: some View {
        VStack(spacing: 10) {
            topControls

            if hasActiveFilters {
                libraryActiveFilterChips
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 8)
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
}

/// One full-screen library page; card is centered in the space between search and tab bar.
private struct CenteredLibraryCardPage: View {
    let word: Word

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ExploreWordPageCard(word: word)
                .padding(.horizontal, 20)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// TikTok-style vertical paging: one swipe always moves exactly one word.
private struct LibraryWordPager: View {
    let words: [Word]
    let pageHeight: CGFloat
    @Binding var scrollPosition: UUID?
    @Binding var scrollRequest: LibraryScrollRequest?
    let onNavigateToWord: (UUID) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(words, id: \.id) { word in
                    CenteredLibraryCardPage(word: word)
                        .frame(height: pageHeight)
                        .frame(maxWidth: .infinity)
                        .id(word.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrollPosition)
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .onChange(of: scrollRequest) { _, request in
            guard let request else { return }
            onNavigateToWord(request.wordID)
        }
    }
}

private struct ExploreWordPageCard: View {
    let word: Word
    @State private var sensePage = 0

    private var originOrHookBody: String? {
        word.cardOriginOrHookBody
    }

    private var originOrHookTitle: String {
        word.cardOriginOrHookTitle
    }

    var body: some View {
        let senses = word.displaySenseBlocks
        let active = senses[safe: sensePage] ?? senses.first

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(word.word)
                    .font(GlanceHubFont.semibold(34))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(HubPalette.espresso)

                WordPronunciationButton(word: word.word, size: 32)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if senses.count > 1 {
                HStack(spacing: 8) {
                    ForEach(Array(senses.enumerated()), id: \.offset) { index, sense in
                        Button {
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

                Text(active.definition)
                    .font(GlanceHubFont.medium(17))
                    .foregroundStyle(HubPalette.espresso)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                Text("Example")
                    .font(GlanceHubFont.semibold(12))
                    .tracking(0.6)
                    .foregroundStyle(HubPalette.plantDeep)
                    .padding(.top, 14)

                Text(active.exampleSentence)
                    .font(GlanceHubFont.regular(16))
                    .italic()
                    .foregroundStyle(HubPalette.espresso)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }

            if let body = originOrHookBody {
                Text(originOrHookTitle)
                    .font(GlanceHubFont.semibold(12))
                    .tracking(0.6)
                    .foregroundStyle(HubPalette.plantDeep)
                    .padding(.top, 14)

                Text(body)
                    .font(GlanceHubFont.regular(16))
                    .foregroundStyle(HubPalette.espresso)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .padding(.top, 6)
            }
        }
        .padding(22)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.22), value: sensePage)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.74),
                                    HubPalette.oatmeal.opacity(0.30),
                                    HubPalette.amberAccent.opacity(0.12),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.82),
                                    HubPalette.ember.opacity(0.16),
                                    Color.black.opacity(0.04),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.075), radius: 22, y: 14)
        )
        .onChange(of: word.id) { _, _ in
            sensePage = 0
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

    @Binding var selectedStatus: LearningStatusFilter?
    @Binding var selectedCategory: PassageDomain?
    @Binding var selectedConnotation: WordConnotationPolarity?

    private var hasActiveFilters: Bool {
        selectedStatus != nil || selectedCategory != nil || selectedConnotation != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Learning status", selection: $selectedStatus) {
                        Text("Any").tag(LearningStatusFilter?.none)
                        ForEach(LearningStatusFilter.allCases) { status in
                            Text(status.label).tag(Optional(status))
                        }
                    }
                    .pickerStyle(.inline)
                } footer: {
                    Text("Filter by how well you know each word.")
                }

                Section {
                    Picker("Passage", selection: $selectedCategory) {
                        Text("Any").tag(PassageDomain?.none)
                        ForEach(PassageDomain.displayOrder) { domain in
                            Text(domain.displayTitle).tag(Optional(domain))
                        }
                    }
                    .pickerStyle(.inline)
                } footer: {
                    Text("Match words to SAT passage themes.")
                }

                Section {
                    Picker("Connotation", selection: $selectedConnotation) {
                        Text("Any").tag(WordConnotationPolarity?.none)
                        ForEach(WordConnotationPolarity.filterOptions, id: \.self) { polarity in
                            Text(polarity.label).tag(Optional(polarity))
                        }
                    }
                    .pickerStyle(.inline)
                } footer: {
                    Text("Filter by emotional charge of the word.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(HubPalette.linen.ignoresSafeArea())
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(HubPalette.linen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        resetFilters()
                    }
                    .disabled(!hasActiveFilters)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .tint(HubPalette.plantDeep)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(HubPalette.linen)
    }

    private func resetFilters() {
        selectedStatus = nil
        selectedCategory = nil
        selectedConnotation = nil
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
                .background(
                    Circle()
                        .fill(isActive ? HubPalette.plantDeep.opacity(0.14) : Color.clear)
                        .background(Circle().fill(.thinMaterial))
                )
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

private enum LearningStatusFilter: String, CaseIterable, Identifiable, Hashable {
    case unseen = "Unseen"
    case learning = "Learning"
    case mastered = "Mastered"

    var id: Self { self }
    var label: String { rawValue }

    static func from(_ status: String) -> Self {
        switch status.lowercased() {
        case "mastered": return .mastered
        case "review", "learning": return .learning
        default: return .unseen
        }
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
