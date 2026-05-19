//
//  SocialBrandIcons.swift
//  GlanceSAT
//

import SwiftUI

enum SocialBrandIcon {
    private static let iconSize: CGFloat = 18
    private static let frameWidth: CGFloat = 26

    static var instagram: some View {
        brandImage("BrandInstagram")
    }

    static var tiktok: some View {
        brandImage("BrandTikTok")
    }

    private static func brandImage(_ name: String) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: iconSize, height: iconSize)
            .foregroundStyle(HubPalette.espresso)
            .frame(width: frameWidth, alignment: .center)
            .accessibilityHidden(true)
    }
}
