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
            "csv", "txt", "md", "markdown", "rtf",
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

struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: FNImportFileTypes.allowed,
            asCopy: false
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true
        picker.modalPresentationStyle = .formSheet
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        context.coordinator.onPick = onPick
        context.coordinator.onCancel = onCancel
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: ([URL]) -> Void
        var onCancel: () -> Void

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
