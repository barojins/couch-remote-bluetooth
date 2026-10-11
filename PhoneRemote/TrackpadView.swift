import SwiftUI
import UIKit

struct TrackpadView: UIViewRepresentable {
    var onCommand: (RemoteCommand) -> Void

    func makeUIView(context: Context) -> TouchSurface {
        let view = TouchSurface()
        view.onCommand = onCommand
        return view
    }

    func updateUIView(_ uiView: TouchSurface, context: Context) { uiView.onCommand = onCommand }
}

final class TouchSurface: UIView {
    var onCommand: ((RemoteCommand) -> Void)?
    private var motion = TrackpadMotion()
    private var scrollMotion = TrackpadMotion()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        let right = UITapGestureRecognizer(target: self, action: #selector(rightClick))
        right.numberOfTouchesRequired = 2
        let single = UITapGestureRecognizer(target: self, action: #selector(click))
        let double = UITapGestureRecognizer(target: self, action: #selector(doubleClick))
        double.numberOfTapsRequired = 2
        single.require(toFail: double)
        single.require(toFail: right)
        double.require(toFail: right)
        addGestureRecognizer(pan)
        addGestureRecognizer(scroll)
        addGestureRecognizer(right)
        addGestureRecognizer(single)
        addGestureRecognizer(double)
        isAccessibilityElement = true
        accessibilityLabel = "Mac trackpad"
        accessibilityHint = "Slide one finger to move. Tap to click, double-tap to double-click, tap two fingers to right-click, or slide two fingers to scroll."
        accessibilityTraits = .allowsDirectInteraction
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { motion = TrackpadMotion() }
        guard gesture.state == .began || gesture.state == .changed || gesture.state == .ended else { return }
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)
        gesture.setTranslation(.zero, in: self)
        if let command = motion.delta(x: translation.x, y: translation.y, speed: hypot(velocity.x, velocity.y)) {
            onCommand?(command)
        }
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { scrollMotion = TrackpadMotion() }
        guard gesture.state == .began || gesture.state == .changed || gesture.state == .ended else { return }
        let translation = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        if let command = scrollMotion.delta(x: translation.x, y: translation.y, speed: 0, scrolling: true) {
            onCommand?(command)
        }
    }

    @objc private func click() { onCommand?(.click) }
    @objc private func doubleClick() { onCommand?(.doubleClick) }
    @objc private func rightClick() { onCommand?(.rightClick) }
}
