//
//  WidgetPayload.swift
//  GlanceSATWidgets — keep Codable fields in sync with host `WidgetSnapshotPayload.swift`.
//

import Foundation

struct WidgetSnapshotPayload: Codable, Sendable {
    var updatedAt: Date
    var words: [WidgetWordSnapshot]
}

struct WidgetWordSnapshot: Codable, Sendable, Identifiable {
    var id: UUID
    var word: String
    var partOfSpeech: String
    var definition: String
    var exampleSentence: String
    var etymology: String?

    static let placeholder = WidgetWordSnapshot(
        id: UUID(),
        word: "Glance",
        partOfSpeech: "noun",
        definition: "Open the app to sync vocabulary for your widgets.",
        exampleSentence: "",
        etymology: nil
    )
}

enum WidgetPayloadLoader {
    private static let appGroup = "group.com.mikihill.GlanceSAT"
    private static let snapshotFilename = "widget_words_snapshot.json"

    static func load() -> WidgetSnapshotPayload {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
              let data = try? Data(contentsOf: dir.appendingPathComponent(snapshotFilename)),
              let decoded = try? JSONDecoder().decode(WidgetSnapshotPayload.self, from: data),
              !decoded.words.isEmpty else {
            return WidgetSnapshotPayload(updatedAt: Date(), words: [WidgetWordSnapshot.placeholder])
        }
        return decoded
    }
}
