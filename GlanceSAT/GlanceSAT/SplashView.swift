//
//  SplashView.swift
//  GlanceSAT
//

import SwiftUI

struct SplashView: View {
    /// Wordmark cream sampled from the brand launch art (`#FFFCF4`, softened slightly warm).
    private let wordmarkCream = Color(red: 0.969, green: 0.949, blue: 0.910)
    /// Base wordmark width as a fraction of the screen (source art ~0.72).
    private let wordmarkWidthFractionBase: CGFloat = 0.72
    /// Visual scale — applied to width, not point size (text scales to fit the frame).
    private let wordmarkVisualScale: CGFloat = 0.8
    private var wordmarkWidthFraction: CGFloat {
        wordmarkWidthFractionBase * wordmarkVisualScale
    }
    /// Large Didot size so glyphs stay sharp after width fitting.
    private let wordmarkFontSize: CGFloat = 240

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            GeometryReader { proxy in
                Text("glance")
                    .font(.custom("Didot-Bold", size: wordmarkFontSize))
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
