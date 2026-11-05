import SwiftUI

struct DocumentImportSheet: View {
    @EnvironmentObject private var store: FreeNoteStore
    @Environment(\.dismiss) private var dismiss

    let allowsCurrentPage: Bool
    let notebookID: UUID?
    let pageID: UUID?

    @State private var destinations: Set<ImportDestination>
    @State private var showingDocumentPicker = false
    @State private var pickedFiles: [PickedImportFile] = []
    @State private var isImporting = false
    @State private var importTask: Task<Void, Never>?
    @State private var activeAlert: ImportAlert?

    init(
        defaultDestination: ImportDestination,
        allowsCurrentPage: Bool,
        notebookID: UUID? = nil,
        pageID: UUID? = nil
    ) {
        let currentPageAvailable = allowsCurrentPage && notebookID != nil && pageID != nil
        let initialDestination = defaultDestination == .currentPage && !currentPageAvailable
            ? .library
            : defaultDestination
        self.allowsCurrentPage = currentPageAvailable
        self.notebookID = notebookID
        self.pageID = pageID
        _destinations = State(initialValue: [initialDestination])
    }

    var body: some View {
        VStack(spacing: 0) {
            FNModalHeader(
                title: "导入文件",
                subtitle: "文件会复制到 FreeNote 沙盒，原文件保持不变。",
                onClose: {
                    guard !isImporting else { return }
                    dismiss()
                }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pickerButton

                    if pickedFiles.isEmpty {
                        formatLegend
                    } else {
                        selectedFileList
                    }

                    Rectangle().fill(FNTheme.divider).frame(height: 1)

                    Text("导入到")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FNTheme.secondaryInk)

                    VStack(spacing: 8) {
                        destinationRow(
                            .bookshelf,
                            title: "书架",
                            subtitle: "适合 PDF、电子书和课件",
                            symbol: "books.vertical"
                        )
                        destinationRow(
                            .library,
                            title: "资源库",
                            subtitle: "适合图片、音频、表格和零散资料",
                            symbol: "folder"
                        )
                        if allowsCurrentPage {
                            destinationRow(
                                .currentPage,
                                title: "当前页面",
                                subtitle: "作为当前笔记页面的附件插入",
                                symbol: "doc.badge.plus"
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }

            Rectangle().fill(FNTheme.divider).frame(height: 1)

            importFooter
        }
        .frame(minWidth: 620, minHeight: 680)
        .background(FNTheme.contentBackground)
        .interactiveDismissDisabled(isImporting)
        .onDisappear {
            importTask?.cancel()
            importTask = nil
        }
        .background(
            DocumentPickerPresenter(
                isPresented: showingDocumentPicker,
                onPick: { urls in
                    showingDocumentPicker = false
                    mergePickedFiles(urls)
                },
                onCancel: {
                    showingDocumentPicker = false
                }
            )
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
        )
        .alert(item: $activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("好")) {
                    if alert.dismissSheet {
                        dismiss()
                    }
                }
            )
        }
    }

    private var pickerButton: some View {
        Button {
            showingDocumentPicker = true
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 29, weight: .light))
                    .foregroundStyle(FNTheme.accent)
                Text(pickedFiles.isEmpty ? "从“文件”选择" : "继续选择文件")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FNTheme.ink)
                Text("支持一次选择多个文件，确认后才能开始导入")
                    .font(.system(size: 10))
                    .foregroundStyle(FNTheme.tertiaryInk)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 142)
            .contentShape(Rectangle())
            .background(FNTheme.accentSoft.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        FNTheme.accent.opacity(0.34),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isImporting)
    }

    private var formatLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("可导入格式")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(FNTheme.secondaryInk)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 82), spacing: 7)],
                alignment: .leading,
                spacing: 7
            ) {
                ForEach(["PDF", "EPUB", "Word", "PPT", "Excel", "CSV", "TXT / MD", "图片", "音频"], id: \.self) { type in
                    Text(type)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(FNTheme.secondaryInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 25)
                        .background(FNTheme.sidebar)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var selectedFileList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已选择 \(pickedFiles.count) 个文件")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FNTheme.ink)
                Spacer()
                Button("全部移除") {
                    pickedFiles.removeAll()
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(FNTheme.danger)
                .buttonStyle(.plain)
                .disabled(isImporting)
            }

            VStack(spacing: 0) {
                ForEach(pickedFiles) { file in
                    HStack(spacing: 10) {
                        Image(systemName: file.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(FNTheme.accent)
                            .frame(width: 36, height: 36)
                            .background(FNTheme.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(FNTheme.ink)
                                .lineLimit(1)
                            Text(file.typeLabel)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(FNTheme.tertiaryInk)
                        }

                        Spacer(minLength: 8)

                        Button {
                            remove(file)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(FNTheme.tertiaryInk)
                        }
                        .buttonStyle(.plain)
                        .disabled(isImporting)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 54)

                    if file.id != pickedFiles.last?.id {
                        Rectangle().fill(FNTheme.divider).frame(height: 1)
                    }
                }
            }
            .background(FNTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(FNTheme.divider, lineWidth: 1)
            )
        }
    }

    private var importSummary: String {
        guard !pickedFiles.isEmpty else { return "请先选择文件" }
        return "将 \(pickedFiles.count) 个文件导入到 \(destinations.count) 个位置"
    }

    private func destinationRow(_ value: ImportDestination, title: String, subtitle: String, symbol: String) -> some View {
        let isSelected = destinations.contains(value)
        return Button {
            toggleDestination(value)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? FNTheme.selectionText : FNTheme.secondaryInk)
                    .frame(width: 34, height: 34)
                    .background(isSelected ? FNTheme.selectionFill : FNTheme.sidebar)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FNTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(FNTheme.tertiaryInk)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? FNTheme.selectionFill : FNTheme.tertiaryInk)
            }
            .padding(11)
            .background(isSelected ? FNTheme.accentSoft.opacity(0.56) : FNTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? FNTheme.accent.opacity(0.4) : FNTheme.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isImporting)
    }

    private func toggleDestination(_ value: ImportDestination) {
        if destinations.contains(value) {
            guard destinations.count > 1 else { return }
            destinations.remove(value)
        } else {
            destinations.insert(value)
        }
    }

    private var importFooter: some View {
        HStack(spacing: 12) {
            if isImporting {
                ProgressView()
                    .controlSize(.small)
                Text("正在复制并识别文件…")
                    .font(.system(size: 10))
                    .foregroundStyle(FNTheme.secondaryInk)
            } else {
                Text(importSummary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FNTheme.tertiaryInk)
            }

            Spacer()

            Button("取消") { dismiss() }
                .buttonStyle(.bordered)
                .disabled(isImporting)
            Button("开始导入", action: startImport)
                .buttonStyle(.borderedProminent)
                .tint(FNTheme.selectionFill)
                .disabled(pickedFiles.isEmpty || isImporting)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(FNTheme.card)
    }

    private func mergePickedFiles(_ urls: [URL]) {
        var knownPaths = Set(pickedFiles.map { $0.url.standardizedFileURL.path })
        for url in urls {
            let standardized = url.standardizedFileURL
            guard !knownPaths.contains(standardized.path) else { continue }
            knownPaths.insert(standardized.path)
            pickedFiles.append(PickedImportFile(url: standardized))
        }
    }

    private func remove(_ file: PickedImportFile) {
        pickedFiles.removeAll { $0.id == file.id }
    }

    private func startImport() {
        guard !isImporting, !pickedFiles.isEmpty, !destinations.isEmpty else { return }
        isImporting = true
        let urls = pickedFiles.map(\.url)
        let requestedDestinations = destinations
        importTask = Task {
            let results = await store.importFiles(
                urls,
                destinations: requestedDestinations,
                notebookID: notebookID,
                pageID: pageID
            )

            guard !Task.isCancelled else { return }
            importTask = nil
            isImporting = false
            pickedFiles.removeAll()

            let succeeded = results.filter(\.success).count
            let failed = results.filter { !$0.success }
            let warnings = results.compactMap(\.warningMessage)
            let warningText = warnings.isEmpty ? "" : "\n\n目录识别提示：\n" + warnings.prefix(5).joined(separator: "\n")

            if failed.isEmpty {
                activeAlert = ImportAlert(
                    title: "导入完成",
                    message: "总计成功导入 \(succeeded) 项。\(warningText)",
                    dismissSheet: true
                )
            } else {
                let details = failed.prefix(3).map { item in
                    "\(item.title)：\(item.errorMessage ?? "未知错误")"
                }.joined(separator: "\n")
                activeAlert = ImportAlert(
                    title: "部分项目导入失败",
                    message: "总计成功 \(succeeded) 项，失败 \(failed.count) 项。\n\(details)\(warningText)\n\n已选文件列表已清空，可关闭后重新选择。",
                    dismissSheet: true
                )
            }
        }
    }
}

private struct PickedImportFile: Identifiable {
    let id = UUID()
    let url: URL

    var name: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension.lowercased() }

    var typeLabel: String {
        let label = fileExtension.isEmpty ? "文件" : fileExtension.uppercased()
        return "\(label) · 待确认"
    }

    var symbol: String {
        switch fileExtension {
        case "pdf": return "doc.richtext"
        case "epub": return "book.closed"
        case "doc", "docx", "docm": return "doc.text"
        case "ppt", "pptx", "pptm": return "rectangle.on.rectangle"
        case "xls", "xlsx", "xlsm", "xlsb", "csv": return "tablecells"
        case "png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "tif", "tiff": return "photo"
        case "mp3", "m4a", "wav", "aac", "flac", "ogg": return "waveform"
        default: return "doc"
        }
    }
}

private struct ImportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let dismissSheet: Bool
}
