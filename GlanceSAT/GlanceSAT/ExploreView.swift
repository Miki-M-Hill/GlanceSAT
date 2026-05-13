//
//  ExploreView.swift
//  GlanceSAT
//

import SwiftData
import SwiftUI

struct ExploreView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Word.word, order: .forward) private var allWords: [Word]
    @FocusState private var isSearchFocused: Bool

    @State private var showFilterSheet = false
    @State private var showSettings = false
    @State private var searchText = ""

    @State private var selectedStatus: Set<LearningStatusFilter> = []
    @State private var selectedScoreBand: Set<ScoreBandFilter> = []
    @State private var selectedContext: Set<PassageContextFilter> = []
    @State private var selectedTone: Set<ToneFilter> = []

    private var filteredWords: [Word] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allWords.filter { word in
            if !selectedStatus.isEmpty, !selectedStatus.contains(.from(word.status)) { return false }
            if !selectedScoreBand.isEmpty, !selectedScoreBand.contains(.from(word.difficulty)) { return false }
            if !selectedContext.isEmpty, !selectedContext.contains(.from(word.category)) { return false }
            if !selectedTone.isEmpty, !selectedTone.contains(.from(word.category)) { return false }

            if query.isEmpty { return true }
            if word.word.lowercased().contains(query) { return true }
            if word.category.lowercased().contains(query) { return true }
            if let ety = word.etymology?.lowercased(), ety.contains(query) { return true }
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
                let headerHeight: CGFloat = 86
                let pageHeight = max(360, proxy.size.height - headerHeight)

                ZStack(alignment: .top) {
                    HubPalette.linen
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: headerHeight)

                        if filteredWords.isEmpty {
                            emptyState
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.horizontal, 20)
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVStack(spacing: 0) {
                                    ForEach(filteredWords, id: \.id) { word in
                                        VStack {
                                            ExploreWordPageCard(word: word)
                                                .padding(.horizontal, 20)
                                                .scrollTransition(.interactive, axis: .vertical) { content, phase in
                                                    content
                                                        .scaleEffect(phase.isIdentity ? 1.0 : 0.94)
                                                        .opacity(phase.isIdentity ? 1.0 : 0.30)
                                                }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: pageHeight)
                                    }
                                }
                                .scrollTargetLayout()
                            }
                            .scrollIndicators(.hidden)
                            .scrollTargetBehavior(.paging)
                            .frame(height: pageHeight)
                        }
                    }

                    libraryHeader
                }
            }
            .background(HubPalette.linen)
            .navigationTitle("Glance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(HubPalette.linen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .tint(HubPalette.espresso)
        }
        .sheet(isPresented: $showFilterSheet) {
            ExploreFilterSheet(
                selectedStatus: $selectedStatus,
                selectedScoreBand: $selectedScoreBand,
                selectedContext: $selectedContext,
                selectedTone: $selectedTone
            )
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(32)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private var libraryHeader: some View {
        VStack(spacing: 0) {
            topControls
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .safeAreaPadding(.top, 6)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(HubPalette.linen.ignoresSafeArea(edges: .top))
    }

    private var librarySearchFillGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.72),
                HubPalette.oatmeal.opacity(0.26),
                HubPalette.amberAccent.opacity(0.10),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var librarySearchStrokeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.78),
                HubPalette.ember.opacity(0.14),
                Color.black.opacity(0.04),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var topControls: some View {
        HStack {
            IconCircleButton(systemName: "line.3.horizontal.decrease") {
                showFilterSheet = true
            }

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
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(librarySearchFillGradient)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(librarySearchStrokeGradient, lineWidth: 1)
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

private struct ExploreWordPageCard: View {
    let word: Word
    @State private var sensePage = 0

    private var etymology: String? {
        word.etymology?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(word.word)
                .font(GlanceHubFont.semibold(34))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(HubPalette.espresso)

            let senses = word.displaySenseBlocks

            if senses.count > 1 {
                HStack(spacing: 6) {
                    ForEach(Array(senses.enumerated()), id: \.offset) { index, sense in
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                sensePage = index
                            }
                        } label: {
                            Text(sense.partOfSpeech)
                                .font(GlanceHubFont.semibold(12))
                                .foregroundStyle(index == sensePage ? HubPalette.linen : HubPalette.espressoMuted)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(index == sensePage ? HubPalette.ember : Color.white.opacity(0.28))
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .strokeBorder(Color.white.opacity(index == sensePage ? 0.16 : 0.44), lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if let only = senses.first {
                Text(only.partOfSpeech)
                    .font(GlanceHubFont.semibold(12))
                    .foregroundStyle(HubPalette.espressoMuted)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(HubPalette.oatmealDeep.opacity(0.45))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.42), lineWidth: 0.7)
                            )
                    )
            }

            Divider()
                .background(HubPalette.espressoFaint)
                .padding(.vertical, 4)

            if let active = senses[safe: sensePage] ?? senses.first {
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
                    .padding(.top, 8)

                Text(active.exampleSentence)
                    .font(GlanceHubFont.regular(16))
                    .italic()
                    .foregroundStyle(HubPalette.espresso)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }

            if let etymology {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                        .background(HubPalette.espressoFaint)
                    Text("Origin")
                        .font(GlanceHubFont.semibold(12))
                        .tracking(0.6)
                        .foregroundStyle(HubPalette.plantDeep)
                    Text(etymology)
                        .font(GlanceHubFont.regular(12))
                        .foregroundStyle(HubPalette.espresso)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
}

private struct ExploreFilterSheet: View {
    @Binding var selectedStatus: Set<LearningStatusFilter>
    @Binding var selectedScoreBand: Set<ScoreBandFilter>
    @Binding var selectedContext: Set<PassageContextFilter>
    @Binding var selectedTone: Set<ToneFilter>

    var body: some View {
        NavigationStack {
            Form {
                filterSection("Learning Status", all: LearningStatusFilter.allCases, selected: $selectedStatus)
                filterSection("Target Score Band", all: ScoreBandFilter.allCases, selected: $selectedScoreBand)
                filterSection("Passage Context", all: PassageContextFilter.allCases, selected: $selectedContext)
                filterSection("Connotation / Tone", all: ToneFilter.allCases, selected: $selectedTone)
            }
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .navigationTitle("Glance")
            .navigationBarTitleDisplayMode(.inline)
            .tint(HubPalette.espresso)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") {
                        selectedStatus.removeAll()
                        selectedScoreBand.removeAll()
                        selectedContext.removeAll()
                        selectedTone.removeAll()
                    }
                    .foregroundStyle(HubPalette.ember)
                }
            }
        }
    }

    private func filterSection<T: ExploreFilterOption>(
        _ title: String,
        all: [T],
        selected: Binding<Set<T>>
    ) -> some View {
        Section(title) {
            ForEach(all) { option in
                Button {
                    if selected.wrappedValue.contains(option) {
                        selected.wrappedValue.remove(option)
                    } else {
                        selected.wrappedValue.insert(option)
                    }
                } label: {
                    HStack {
                        Text(option.label)
                        Spacer()
                        if selected.wrappedValue.contains(option) {
                            Image(systemName: "checkmark")
                                .font(GlanceHubFont.semibold(12))
                                .foregroundStyle(HubPalette.ember)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct IconCircleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(GlanceHubFont.semibold(16))
                .foregroundStyle(HubPalette.espresso)
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(.thinMaterial)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.58), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private protocol ExploreFilterOption: CaseIterable, Identifiable, Hashable {
    var label: String { get }
}

private enum LearningStatusFilter: String, CaseIterable, Identifiable, ExploreFilterOption {
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

private enum ScoreBandFilter: String, CaseIterable, Identifiable, ExploreFilterOption {
    case core = "Core (1200+)"
    case advanced = "Advanced (1400+)"
    case elite = "Elite (1500+)"

    var id: Self { self }
    var label: String { rawValue }

    static func from(_ difficulty: Int) -> Self {
        switch difficulty {
        case 1 ... 2: return .core
        case 3 ... 4: return .advanced
        default: return .elite
        }
    }
}

private enum PassageContextFilter: String, CaseIterable, Identifiable, ExploreFilterOption {
    case literature = "Literature"
    case historyCivics = "History/Civics"
    case science = "Science"

    var id: Self { self }
    var label: String { rawValue }

    static func from(_ category: String) -> Self {
        let c = category.lowercased()
        if c.contains("history") || c.contains("logic") || c.contains("social") || c.contains("behavior") {
            return .historyCivics
        }
        if c.contains("science") || c.contains("environment") || c.contains("engineering") {
            return .science
        }
        return .literature
    }
}

private enum ToneFilter: String, CaseIterable, Identifiable, ExploreFilterOption {
    case positive = "Positive"
    case negative = "Negative"
    case objective = "Objective"

    var id: Self { self }
    var label: String { rawValue }

    static func from(_ category: String) -> Self {
        let c = category.lowercased()
        if c.contains("social") || c.contains("behavior") { return .objective }
        if c.contains("history") || c.contains("environment") { return .negative }
        return .positive
    }
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
