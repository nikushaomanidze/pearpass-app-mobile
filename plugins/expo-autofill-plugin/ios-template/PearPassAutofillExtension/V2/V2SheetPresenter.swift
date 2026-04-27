//
//  V2SheetPresenter.swift
//  PearPassAutoFillExtension
//
//  Configures the sheet presentation style for V2 screens to mirror Android's
//  Theme.PearPass.Autofill.Fullscreen.V2 — partial-height (~85%), bottom-anchored,
//  dim backdrop, edge-to-edge.
//

import UIKit

enum V2SheetPresenter {

    /// Configures `viewController` for V2 sheet presentation.
    /// On iOS 16+ uses `UISheetPresentationController` with a 0.85 fraction detent.
    /// On older iOS versions falls back to fullscreen (extension hosts the whole window).
    static func configure(_ viewController: UIViewController) {
        if #available(iOS 16.0, *) {
            viewController.modalPresentationStyle = .pageSheet
            if let sheet = viewController.sheetPresentationController {
                sheet.detents = [
                    .custom(identifier: .init("pearpass.v2.partial")) { context in
                        context.maximumDetentValue * 0.85
                    }
                ]
                sheet.prefersGrabberVisible = false
                sheet.preferredCornerRadius = 0
                sheet.prefersEdgeAttachedInCompactHeight = true
                sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = false
            }
        } else {
            viewController.modalPresentationStyle = .overFullScreen
        }
    }
}
