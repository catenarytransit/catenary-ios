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

private final class NativeSheetToolbarContentView: UIView {
    private let contentView: UIView & UIContentView

    init(configuration: UIHostingConfiguration<AnyView, EmptyView>) {
        contentView = configuration.makeContentView()
        super.init(frame: .zero)

        backgroundColor = .clear
        isUserInteractionEnabled = true

        contentView.backgroundColor = .clear
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(configuration: UIHostingConfiguration<AnyView, EmptyView>) {
        contentView.configuration = configuration
        contentView.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        let measured = contentView.systemLayoutSizeFitting(
            UIView.layoutFittingCompressedSize,
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )

        // A standalone UIHostingConfiguration content view is normally sized by
        // a table/collection cell. When used as a free-floating view it can report
        // no intrinsic size, which collapses the FAB to 0x0. Preserve the measured
        // SwiftUI size when available and keep a conservative toolbar-sized floor
        // as a fallback so the accessory can never disappear from Auto Layout.
        return CGSize(
            width: max(measured.width.rounded(.up), 56),
            height: max(measured.height.rounded(.up), 104)
        )
    }
}

final class NativeSheetFloatingToolbarController: UIViewController {
    private var toolbarView: NativeSheetToolbarContentView?
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
            toolbarView.update(configuration: hostingConfiguration(for: content))
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

        let toolbarView: NativeSheetToolbarContentView
        if let existingToolbarView = self.toolbarView {
            toolbarView = existingToolbarView
        } else {
            let newToolbarView = NativeSheetToolbarContentView(
                configuration: hostingConfiguration(for: content)
            )
            newToolbarView.translatesAutoresizingMaskIntoConstraints = false
            newToolbarView.setContentHuggingPriority(.required, for: .horizontal)
            newToolbarView.setContentHuggingPriority(.required, for: .vertical)
            newToolbarView.setContentCompressionResistancePriority(.required, for: .horizontal)
            newToolbarView.setContentCompressionResistancePriority(.required, for: .vertical)
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

        toolbarView.isHidden = false
        containerView.bringSubviewToFront(toolbarView)
        containerView.setNeedsLayout()
        containerView.layoutIfNeeded()
    }

    private func detachToolbar() {
        NSLayoutConstraint.deactivate(attachmentConstraints)
        attachmentConstraints.removeAll()
        toolbarView?.removeFromSuperview()
        attachedSheetView = nil
        attachedContainerView = nil
    }

    private var containingPresentedController: UIViewController? {
        var controller: UIViewController? = self

        while let current = controller {
            if current.presentingViewController != nil,
               current.presentationController?.presentedViewController === current {
                return current
            }
            controller = current.parent
        }

        return nil
    }
}
