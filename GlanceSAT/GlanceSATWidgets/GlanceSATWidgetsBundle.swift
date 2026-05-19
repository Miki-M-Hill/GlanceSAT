//
//  GlanceSATWidgetsBundle.swift
//  GlanceSATWidgets
//

import SwiftUI
import WidgetKit

@main
struct GlanceSATWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GlanceSATVocabularyWidget()
        GlanceSATQuizWidget()
    }
}
