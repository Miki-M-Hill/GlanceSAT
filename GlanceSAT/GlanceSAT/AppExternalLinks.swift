//
//  AppExternalLinks.swift
//  GlanceSAT
//

import StoreKit
import SwiftUI
import UIKit

/// Central URLs and App Store Connect wiring for Settings actions.
enum AppExternalLinks {
  private static let placeholderAppStoreIDs: Set<String> = ["", "000000000", "REPLACE_ME"]

  // MARK: - App Store Connect

  /// Numeric Apple ID from App Store Connect → App Information (not the bundle ID).
  /// Set `AppStoreAppleID` in GlanceSAT-Info.plist after you create the app record.
  static var appStoreAppleID: String? {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: "AppStoreAppleID") as? String else {
      return nil
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !placeholderAppStoreIDs.contains(trimmed) else { return nil }
    return trimmed
  }

  static var appStoreProductURL: URL? {
    guard let id = appStoreAppleID else { return nil }
    return URL(string: "https://apps.apple.com/app/id\(id)")
  }

  static var appStoreReviewURL: URL? {
    guard let id = appStoreAppleID else { return nil }
    return URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
  }

  /// Used by Share Glance until the App Store listing is live.
  static var marketingShareURL: URL {
    URL(string: "https://www.glanceprep.com")!
  }

  static var shareItemURL: URL {
    appStoreProductURL ?? marketingShareURL
  }

  // MARK: - Web (in-app Safari)

  static let help = URL(string: "https://www.glanceprep.com/support")!
  static let privacy = URL(string: "https://www.glanceprep.com/privacy")!
  static let terms = URL(string: "https://www.glanceprep.com/terms")!

  // MARK: - Social

  static let instagramWeb = URL(
    string: "https://www.instagram.com/glance_sat?igsh=MWNiN2ZuZXh2MDF0cA%3D%3D&utm_source=qr"
  )!
  static let tiktokWeb = URL(string: "https://www.tiktok.com/@glance_sat")!

  private static let instagramApp = URL(string: "instagram://user?username=glance_sat")

  // MARK: - Actions

  @MainActor
  static func openManageSubscriptions(using openURL: OpenURLAction) async {
    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
      do {
        try await AppStore.showManageSubscriptions(in: scene)
        return
      } catch {
        // Fall through to Apple's account subscriptions page.
      }
    }
    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
      openURL(url)
    }
  }

  @MainActor
  static func openInstagram(using openURL: OpenURLAction) {
    openSocial(appURL: instagramApp, webURL: instagramWeb, using: openURL)
  }

  @MainActor
  static func openTikTok(using openURL: OpenURLAction) {
    // Universal link — iOS hands off to TikTok at @glance_sat when installed (tiktok:// only opens the app home).
    openURL(tiktokWeb)
  }

  @MainActor
  private static func openSocial(appURL: URL?, webURL: URL, using openURL: OpenURLAction) {
    if let appURL, UIApplication.shared.canOpenURL(appURL) {
      openURL(appURL)
    } else {
      openURL(webURL)
    }
  }
}
