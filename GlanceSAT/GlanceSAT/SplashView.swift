//
//  SplashView.swift
//  GlanceSAT
//

import SwiftUI

struct SplashView: View {
    /// Wordmark cream sampled from the brand launch art (`#FFFCF4`, softened slightly warm).
    private let wordmarkCream = Color(red: 0.969, green: 0.949, blue: 0.910)
    /// Target wordmark width as a fraction of the screen (matches the source art ~0.71).
    private let wordmarkWidthFraction: CGFloat = 0.72

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            GeometryReader { proxy in
                Text("glance")
                    .font(.custom("Didot", size: 240))
                    .lineLimit(1)
                    .minimumScaleFactor(0.01)
                    .foregroundStyle(wordmarkCream)
                    .frame(width: proxy.size.width * wordmarkWidthFraction)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .ignoresSafeArea()
        }
        .accessibilityLabel("Glance")
    }
}
