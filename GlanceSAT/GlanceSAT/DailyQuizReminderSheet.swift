//
//  DailyQuizReminderSheet.swift
//  GlanceSAT
//

import SwiftUI

/// Daily quiz notification time — used from Settings and synced with onboarding ritual prefs.
struct DailyQuizReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("dailyQuizReminderHour") private var reminderHour = 19
    @AppStorage("dailyQuizReminderMinute") private var reminderMinute = 0
    @AppStorage("quizReminderTime") private var quizReminderTimeInterval: Double = 0

    @State private var draftTime: Date
    @State private var isSaving = false

    init() {
        _draftTime = State(initialValue: NotificationManager.preferredReminderDate())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("We'll remind you when your daily recall quiz is ready.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(HubPalette.espressoMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                DatePicker(
                    "Daily quiz reminder",
                    selection: $draftTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .tint(HubPalette.espresso)
                .padding(.horizontal, 8)

                Spacer(minLength: 0)
            }
            .background(HubPalette.linen)
            .navigationTitle("Daily Quiz Reminder")
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
                        Task { await saveReminderTime() }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(HubPalette.espresso)
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @MainActor
    private func saveReminderTime() async {
        guard !isSaving else { return }
        isSaving = true

        let components = Calendar.current.dateComponents([.hour, .minute], from: draftTime)
        let hour = components.hour ?? 19
        let minute = components.minute ?? 0

        reminderHour = hour
        reminderMinute = minute
        quizReminderTimeInterval = draftTime.timeIntervalSince1970

        await NotificationManager.updatePreferredReminderTime(hour: hour, minute: minute)
        dismiss()
    }
}
