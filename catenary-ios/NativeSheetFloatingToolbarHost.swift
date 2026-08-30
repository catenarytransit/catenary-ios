//
//  NativeSheetFloatingToolbarHost.swift
//  catenary-ios
//

import SwiftUI
import UIKit

/// Mounts the portrait-phone floating toolbar in the same UIKit presentation
/// container as the native sheet and constrains it directly to the sheet's top
/// edge. UIKit then moves both views in the same layout/animation transaction,
/// avoiding a SwiftUI geometry -> state -> offset feedback loop.
struct NativeSheetFloatingToolbarHost<Content: View>: UIViewControllerRepresentable {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> NativeSheetFloatingToolbarController {
        let controller = NativeSheetFloatingToolbarController()
        controller.update(content: AnyView(content))
        return controller
    }

    func updateUIViewController(
        _ uiViewController: NativeSheetFloatingToolbarController,
        context: Context
    ) {
        uiViewController.update(content: AnyView(content))
    }
}

private final class NativeSheetFloatingToolbarController: UIViewController {
    private var toolbarView: (UIView & UIContentView)?
    private var toolbarContent: AnyView?
    private weak var attachedSheetView: UIView?
    private weak var attachedContainerView: UIView?
    private var attachmentConstraints: [NSLayoutConstraint] = []
    private var delayedAttachment: DispatchWorkItem?

    override func loadView() {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        self.view = view
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleAttachment()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        attachToolbarIfPossible()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        detachToolbar()
    }

    deinit {
        delayedAttachment?.cancel()
        detachToolbar()
    }

    func update(content: AnyView) {
        toolbarContent = content

        if let toolbarView {
            toolbarView.configuration = hostingConfiguration(for: content)
        }

        scheduleAttachment()
    }

    private func hostingConfiguration(
        for content: AnyView
    ) -> UIHostingConfiguration<AnyView, EmptyView> {
        UIHostingConfiguration {
            content
        }
        .margins(.all, 0)
    }

    private func scheduleAttachment() {
        attachToolbarIfPossible()

        delayedAttachment?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.attachToolbarIfPossible()
        }
        delayedAttachment = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func attachToolbarIfPossible() {
        guard let content = toolbarContent,
              let sheetController = containingPresentedController,
              let presentationController = sheetController.presentationController,
              let containerView = presentationController.containerView,
              let sheetView = presentationController.presentedView else {
            return
        }

        let toolbarView: UIView & UIContentView
        if let existingToolbarView = self.toolbarView {
            toolbarView = existingToolbarView
        } else {
            let newToolbarView = hostingConfiguration(for: content).makeContentView()
            newToolbarView.backgroundColor = .clear
            newToolbarView.translatesAutoresizingMaskIntoConstraints = false
            self.toolbarView = newToolbarView
            toolbarView = newToolbarView
        }

        let attachmentChanged = attachedSheetView !== sheetView
            || attachedContainerView !== containerView
            || toolbarView.superview !== containerView

        if attachmentChanged {
            NSLayoutConstraint.deactivate(attachmentConstraints)
            attachmentConstraints.removeAll()
            toolbarView.removeFromSuperview()
            containerView.addSubview(toolbarView)

            attachmentConstraints = [
                toolbarView.trailingAnchor.constraint(
                    equalTo: containerView.safeAreaLayoutGuide.trailingAnchor,
                    constant: -15
                ),
                toolbarView.bottomAnchor.constraint(
                    equalTo: sheetView.topAnchor,
                    constant: -8
                )
            ]
            NSLayoutConstraint.activate(attachmentConstraints)

            attachedSheetView = sheetView
            attachedContainerView = containerView
        }

        containerView.bringSubviewToFront(toolbarView)
    }

    private func detachToolbar() {
        NSLayoutConstraint.deactivate(attachmentConstraints)
        attachmentConstraints.removeAll()
        toolbarView?.removeFromSuperview()
        attachedSheetView = nil
        attachedContainerView = nil
    }
