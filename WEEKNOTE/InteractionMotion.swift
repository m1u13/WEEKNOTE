import SwiftUI
import UIKit

enum InteractionMotion {
    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.32)
    }

    static func pageTransition(direction: Int, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: direction >= 0 ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: direction >= 0 ? .leading : .trailing).combined(with: .opacity)
        )
    }

    @MainActor static func selectionFeedback() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

private struct HorizontalPageSwipe: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onChange: (Int) -> Void
    @GestureState private var horizontalOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content.offset(x: reduceMotion ? 0 : horizontalOffset)
            .animation(InteractionMotion.animation(reduceMotion: reduceMotion), value: horizontalOffset == 0)
            .simultaneousGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .global)
                .updating($horizontalOffset) { value, offset, transaction in
                    transaction.animation = nil
                    if abs(value.translation.width) > abs(value.translation.height) * 1.4 {
                        offset = max(-72, min(72, value.translation.width * 0.22))
                    }
                }
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    // Vertical scrolling continues in the enclosing ScrollView.
                    // Only a deliberate horizontal movement changes the period.
                    guard abs(horizontal) >= 48, abs(horizontal) > abs(vertical) * 1.4 else { return }
                    InteractionMotion.selectionFeedback()
                    withAnimation(InteractionMotion.animation(reduceMotion: reduceMotion)) {
                        onChange(horizontal < 0 ? 1 : -1)
                    }
                }
        )
    }
}

extension View {
    /// A left swipe requests the next period (+1); a right swipe requests the previous period (-1).
    func horizontalPageSwipe(onChange: @escaping (Int) -> Void) -> some View {
        modifier(HorizontalPageSwipe(onChange: onChange))
    }
}
