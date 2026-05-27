//
//  SplashView.swift
//  GlanceSAT
//

import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            HubPalette.dailyHubGreen
                .ignoresSafeArea()

            Text("GLANCE")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .tracking(4)
                .foregroundStyle(HubPalette.linen)
        }
        .accessibilityLabel("Glance")
    }
}
