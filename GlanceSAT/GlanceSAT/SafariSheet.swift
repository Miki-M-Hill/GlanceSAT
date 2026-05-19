//
//  SafariSheet.swift
//  GlanceSAT
//

import SafariServices
import SwiftUI
import UIKit

/// Presents a Glance website page in an in-app Safari sheet (not the external Safari app).
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true

        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        controller.preferredBarTintColor = UIColor(HubPalette.linen)
        controller.preferredControlTintColor = UIColor(HubPalette.espresso)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

/// Identifiable wrapper so `.sheet(item:)` can present a URL.
struct PresentableWebURL: Identifiable {
    let id = UUID()
    let url: URL
}
