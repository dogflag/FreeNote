import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum FNImportFileTypes {
    static let allowed: [UTType] = {
        var types: [UTType] = [.pdf, .image, .audio, .plainText]
        let extensions = [
            "epub",
            "doc", "docx", "docm",
            "ppt", "pptx", "pptm",
            "xls", "xlsx", "xlsm", "xlsb",
            "csv", "txt", "md", "markdown", "rtf", "html", "htm",
            "png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "tif", "tiff",
            "mp3", "m4a", "wav", "aac", "flac", "ogg"
        ]
        for fileExtension in extensions {
            if let type = UTType(filenameExtension: fileExtension), !types.contains(type) {
                types.append(type)
            }
        }
        let officeIdentifiers = [
            "org.openxmlformats.spreadsheetml.sheet",
            "com.microsoft.excel.xls",
            "org.openxmlformats.wordprocessingml.document",
            "org.openxmlformats.presentationml.presentation"
        ]
        for identifier in officeIdentifiers {
            let type = UTType(importedAs: identifier)
            if !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }()
}

struct DocumentPickerPresenter: UIViewControllerRepresentable {
    let isPresented: Bool
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        context.coordinator.host = host
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updatePresentation()
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
        var parent: DocumentPickerPresenter?
        weak var host: UIViewController?
        weak var picker: UIDocumentPickerViewController?
        private var requestedState = false
        private var isPresenting = false
        private var isScheduling = false
        private var attemptCount = 0
        private let maximumAttempts = 20

        func updatePresentation() {
            let wanted = parent?.isPresented == true
            if wanted {
                if !requestedState {
                    requestedState = true
                    attemptCount = 0
                }
                requestPresentation()
            } else {
                requestedState = false
                attemptCount = 0
                if isPresenting {
                    dismissPicker()
                }
            }
        }

        private func requestPresentation() {
            guard requestedState, !isPresenting, !isScheduling else { return }
            isScheduling = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isScheduling = false
                guard self.requestedState else { return }
                self.attemptPresentation()
            }
        }

        private func attemptPresentation() {
            guard requestedState, !isPresenting else { return }
            attemptCount += 1

            guard let host, host.view.window != nil else {
                scheduleRetryOrFail()
                return
            }
            guard host.presentedViewController == nil else {
                scheduleRetryOrFail()
                return
            }

            let controller = UIDocumentPickerViewController(
                forOpeningContentTypes: FNImportFileTypes.allowed,
                asCopy: true
            )
            controller.delegate = self
            controller.allowsMultipleSelection = true
            controller.modalPresentationStyle = .formSheet
            picker = controller
            isPresenting = true

            host.present(controller, animated: true) { [weak self, weak host, weak controller] in
                guard let self else { return }
                guard self.requestedState else {
                    self.isPresenting = false
                    self.picker = nil
                    if let controller, controller.presentingViewController != nil {
                        controller.dismiss(animated: false)
                    }
                    return
                }
                if host?.presentedViewController === controller {
                    controller?.presentationController?.delegate = self
                    self.attemptCount = 0
                } else {
                    self.isPresenting = false
                    self.picker = nil
                    self.scheduleRetryOrFail()
                }
            }
        }

        private func scheduleRetryOrFail() {
            guard requestedState else { return }
            guard attemptCount < maximumAttempts else {
                failPresentation()
                return
            }
            isScheduling = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                self.isScheduling = false
                self.requestPresentation()
            }
        }

        private func failPresentation() {
            guard requestedState else { return }
            requestedState = false
            isPresenting = false
            isScheduling = false
            picker = nil
            parent?.onCancel()
        }

        private func dismissPicker() {
            requestedState = false
            isPresenting = false
            picker?.dismiss(animated: true) { [weak self] in
                self?.picker = nil
            }
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            let completion = parent?.onPick
            requestedState = false
            isPresenting = false
            controller.dismiss(animated: true)
            picker = nil
            completion?(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            let completion = parent?.onCancel
            requestedState = false
            isPresenting = false
            controller.dismiss(animated: true)
            picker = nil
            completion?()
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            guard isPresenting || requestedState else { return }
            requestedState = false
            isPresenting = false
            picker = nil
            parent?.onCancel()
        }
    }
}


