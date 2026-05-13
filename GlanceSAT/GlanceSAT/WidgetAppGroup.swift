//
//  WidgetAppGroup.swift
//  GlanceSAT
//

import Foundation

enum WidgetAppGroup {
    /// Must match GlanceSATWidgets.entitlements and the host app entitlements.
    static let identifier = "group.com.mikihill.GlanceSAT"

    static let snapshotFilename = "widget_words_snapshot.json"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}
