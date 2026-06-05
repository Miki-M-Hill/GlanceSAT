//
//  GlanceCelebrationConfettiView.swift
//  GlanceSAT
//

import SwiftUI
import UIKit

struct GlanceCelebrationConfettiView: UIViewRepresentable {
    func makeUIView(context: Context) -> GlanceCelebrationConfettiContainerView {
        GlanceCelebrationConfettiContainerView()
    }

    func updateUIView(_ uiView: GlanceCelebrationConfettiContainerView, context: Context) {}
}

final class GlanceCelebrationConfettiContainerView: UIView {
    private var emitterLayer: CAEmitterLayer?
    private var didStartBurst = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitterLayer?.emitterPosition = CGPoint(x: bounds.midX, y: -8)
        emitterLayer?.emitterSize = CGSize(width: bounds.width, height: 2)
        guard !didStartBurst, bounds.width > 20, bounds.height > 20 else { return }
        didStartBurst = true
        startBurst()
    }

    private func startBurst() {
        emitterLayer?.removeFromSuperlayer()

        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.emitterMode = .outline
        emitter.renderMode = .unordered
        emitter.birthRate = 1

        let palette: [UIColor] = [
            .glanceHub(HubPalette.plantPot),
            .glanceHub(HubPalette.ember),
            UIColor(red: 0.98, green: 0.62, blue: 0.12, alpha: 1),
            UIColor(red: 0.32, green: 0.58, blue: 0.98, alpha: 1),
            UIColor(red: 0.72, green: 0.38, blue: 0.95, alpha: 1),
            UIColor(red: 0.98, green: 0.35, blue: 0.52, alpha: 1),
            .glanceHub(HubPalette.plantDeep),
        ]

        emitter.emitterCells = palette.enumerated().map { index, color in
            makeCell(color: color, variant: index)
        }

        layer.addSublayer(emitter)
        emitterLayer = emitter
        setNeedsLayout()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak emitter] in
            emitter?.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { [weak self, weak emitter] in
            emitter?.removeFromSuperlayer()
            if self?.emitterLayer === emitter {
                self?.emitterLayer = nil
            }
        }
    }

    private func makeCell(color: UIColor, variant: Int) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.birthRate = Float(6 + variant % 4)
        cell.lifetime = Float(5.5 + Double(variant % 3) * 0.4)
        cell.velocity = CGFloat(140 + variant * 8)
        cell.velocityRange = 70
        cell.emissionLongitude = .pi
        cell.emissionRange = .pi / 5
        cell.spin = CGFloat(2.5 + Double(variant) * 0.35)
        cell.spinRange = 3.2
        cell.scale = 0.45
        cell.scaleRange = 0.2
        cell.scaleSpeed = -0.04
        cell.alphaSpeed = -0.18
        cell.yAcceleration = 180
        cell.xAcceleration = CGFloat((variant % 5) - 2) * 6
        cell.contents = confettiImage(isCircle: variant.isMultiple(of: 3), variant: variant).cgImage
        cell.color = color.cgColor
        return cell
    }

    private func confettiImage(isCircle: Bool, variant: Int) -> UIImage {
        let width: CGFloat = isCircle ? 8 : (variant.isMultiple(of: 2) ? 6 : 10)
        let height: CGFloat = isCircle ? 8 : (variant.isMultiple(of: 2) ? 12 : 6)
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIColor.white.setFill()
            let path: UIBezierPath
            if isCircle {
                path = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size))
            } else {
                path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2)
            }
            path.fill()
        }
    }
}

private extension UIColor {
    static func glanceHub(_ color: Color) -> UIColor {
        UIColor(color)
    }
}
