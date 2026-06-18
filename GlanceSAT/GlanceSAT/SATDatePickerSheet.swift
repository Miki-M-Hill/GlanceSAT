//
//  SATDatePickerSheet.swift
//  GlanceSAT
//

import SwiftUI

/// Standalone SAT test date picker — used from Settings and widget deep links.
struct SATDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SATExamDateStore.storageKey) private var satExamDateSeconds: Double = 0

    @State private var draftDate: Date

    init() {
        let resolved = SATExamDateStore.examDate
            ?? Calendar.current.date(byAdding: .month, value: 4, to: Date())
            ?? Date()
        _draftDate = State(initialValue: resolved)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker(
                    "SAT test date",
                    selection: $draftDate,
                    in: Date() ... Calendar.current.date(byAdding: .year, value: 3, to: Date())!,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(HubPalette.espresso)
                .padding(.horizontal, 8)
                .padding(.top, 12)

                Spacer(minLength: 0)
            }
            .background(HubPalette.linen)
            .navigationTitle("SAT Date")
            .glanceNavigationBarChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(HubPalette.espressoMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        SATExamDateStore.save(draftDate)
                        satExamDateSeconds = draftDate.timeIntervalSince1970
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(HubPalette.espresso)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
