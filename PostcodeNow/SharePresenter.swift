import SwiftUI
import UIKit

struct SharePresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var text: String
    var interfaceStyle: UIUserInterfaceStyle

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard isPresented, controller.presentedViewController == nil, !context.coordinator.isPresenting else {
            return
        }
        guard !text.isEmpty else { return }
        context.coordinator.isPresenting = true
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        activity.overrideUserInterfaceStyle = interfaceStyle
        if let popover = activity.popoverPresentationController {
            popover.sourceView = controller.view
            let bounds = controller.view.bounds
            popover.sourceRect = CGRect(x: bounds.midX, y: bounds.maxY - 48, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        activity.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async {
                context.coordinator.isPresenting = false
                isPresented = false
            }
        }
        controller.present(activity, animated: true)
    }

    final class Coordinator {
        var isPresenting = false
    }
}
