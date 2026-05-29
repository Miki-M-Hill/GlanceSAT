//
//  GlanceSATCountdownWidget.swift
//  GlanceSATWidgets
//

import SwiftUI
import WidgetKit

enum GlanceSATCountdownWidgetConstants {
    static let kind = "com.mikihill.GlanceSAT.countdown"
}

struct GlanceSATCountdownEntry: TimelineEntry {
    let date: Date
    let daysRemaining: Int?
    let hasExamDate: Bool
}

struct GlanceSATCountdownProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceSATCountdownEntry {
        GlanceSATCountdownEntry(date: Date(), daysRemaining: 42, hasExamDate: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceSATCountdownEntry) -> Void) {
        completion(makeEntry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceSATCountdownEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let entry = makeEntry(for: now)
        let nextRefresh = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func makeEntry(for date: Date) -> GlanceSATCountdownEntry {
        let hasDate = WidgetPrefsReader.hasSATExamDate()
        let days = WidgetPrefsReader.daysUntilSAT(from: date)
        return GlanceSATCountdownEntry(date: date, daysRemaining: days, hasExamDate: hasDate)
    }
}

struct GlanceSATCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GlanceSATCountdownWidgetConstants.kind, provider: GlanceSATCountdownProvider()) { entry in
            GlanceSATCountdownWidgetView(entry: entry)
                .glanceWidgetBackground(themeName: WidgetPrefsReader.themeName())
        }
        .configurationDisplayName("SAT Countdown")
        .description("Days until your SAT — set your test date in Glance settings.")
        .contentMarginsDisabled()
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct GlanceSATCountdownWidgetView: View {
    let entry: GlanceSATCountdownEntry

    @Environment(\.widgetFamily) private var family

    private var palette: WidgetPalette { WidgetPalette.named(WidgetPrefsReader.themeName()) }

    var body: some View {
        ZStack {
            Color.clear
                .widgetURL(WidgetDeepLink.settingsURL())

            VStack(spacing: contentSpacing) {
                Spacer(minLength: 0)

                if entry.hasExamDate, let days = entry.daysRemaining {
                    activeCountdown(days: days)
                } else {
                    inactivePrompt
                }

                Spacer(minLength: 0)
            }
            .padding(insets)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func activeCountdown(days: Int) -> some View {
        VStack(spacing: numberSpacing) {
            if days < 0 {
                Text("Past")
                    .font(.system(size: headlineSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.secondary)
                Text("Update your SAT date in settings")
                    .font(.system(size: bodySize, weight: .regular, design: .rounded))
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            } else {
                Text("\(max(0, days))")
                    .font(.system(size: numberSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .widgetAccentable()

                Text(days == 1 ? "day to go" : "days to go")
                    .font(.system(size: headlineSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.primary)
                    .multilineTextAlignment(.center)

                Text("until the SAT")
                    .font(.system(size: bodySize, weight: .regular, design: .rounded))
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var inactivePrompt: some View {
        VStack(spacing: numberSpacing) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(palette.primary)
                .widgetAccentable()

            Text("Set your SAT date")
                .font(.system(size: headlineSize, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.primary)
                .multilineTextAlignment(.center)

            Text("Open Glance settings to activate this countdown.")
                .font(.system(size: bodySize, weight: .regular, design: .rounded))
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(family == .systemSmall ? 4 : 3)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    private var insets: EdgeInsets {
        switch family {
        case .systemSmall:
            return EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        case .systemMedium:
            return EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        default:
            return EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
        }
    }

    private var numberSize: CGFloat {
        switch family {
        case .systemSmall: return 52
        case .systemMedium: return 64
        default: return 72
        }
    }

    private var headlineSize: CGFloat {
        switch family {
        case .systemSmall: return 15
        case .systemMedium: return 17
        default: return 19
        }
    }

    private var bodySize: CGFloat {
        switch family {
        case .systemSmall: return 12
        case .systemMedium: return 13
        default: return 14
        }
    }

    private var iconSize: CGFloat {
        switch family {
        case .systemSmall: return 28
        case .systemMedium: return 32
        default: return 36
        }
    }

    private var contentSpacing: CGFloat { 8 }
    private var numberSpacing: CGFloat { family == .systemSmall ? 4 : 6 }
}
