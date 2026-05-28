//
//  SplashView.swift
//  GlanceSAT
//

import SwiftUI

struct SplashView: View {
    var body: some View {
        Image("LaunchBackground")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()
            .accessibilityLabel("Glance")
    }
}
