import SwiftUI
import UIKit

// Screens that hide the system navigation bar (custom top bars, e.g. the
// chat) lose UIKit's interactive edge-swipe-back for free. This proxy digs
// out the enclosing UINavigationController and re-arms the gesture, guarded
// so it never fires on a stack root (which would freeze the UI).

private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { Proxy() }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    private final class Proxy: UIViewController, UIGestureRecognizerDelegate {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            arm()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            arm()
        }

        private func arm() {
            guard let pop = navigationController?.interactivePopGestureRecognizer else { return }
            pop.delegate = self
            pop.isEnabled = true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}

extension View {
    /// Keep the edge-swipe back gesture alive on screens with a hidden
    /// navigation bar. No-op when the view isn't inside a navigation push
    /// (sheets, split-view detail panes).
    func swipeBackEnabled() -> some View {
        background(SwipeBackEnabler().frame(width: 0, height: 0))
    }
}
