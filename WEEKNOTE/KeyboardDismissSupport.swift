import SwiftUI
import UIKit

/// Observes taps without consuming the controls' own gestures. Text input taps
/// keep focus; other taps end editing in the current sheet.
private struct KeyboardDismissObserver: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        view.windowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateUIView(_ uiView: WindowObserverView, context: Context) {
        context.coordinator.attach(to: uiView.window)
    }

    static func dismantleUIView(_ uiView: WindowObserverView, coordinator: Coordinator) {
        coordinator.attach(to: nil)
        uiView.windowChanged = nil
    }

    final class WindowObserverView: UIView {
        var windowChanged: ((UIWindow?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            windowChanged?(window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private lazy var recognizer: UITapGestureRecognizer = {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
            gesture.delegate = self
            return gesture
        }()

        func attach(to newWindow: UIWindow?) {
            guard window !== newWindow else { return }
            window?.removeGestureRecognizer(recognizer)
            window = newWindow
            newWindow?.addGestureRecognizer(recognizer)
        }

        @objc private func dismissKeyboard() { window?.endEditing(true) }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var touchedView = touch.view
            while let view = touchedView {
                if view is UITextField || view is UITextView || view is UISearchBar { return false }
                touchedView = view.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}

extension View {
    func dismissKeyboardOnBackgroundTap() -> some View {
        background(KeyboardDismissObserver().frame(width: 0, height: 0).accessibilityHidden(true))
    }
}
