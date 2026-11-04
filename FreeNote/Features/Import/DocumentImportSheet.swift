import SwiftUI
import UniformTypeIdentifiers

struct DocumentImportSheet: View {
    @EnvironmentObject private var store: FreeNoteStore
    @Environment(\.dismiss) private var dismiss

    let allowsCurrentPage: Bool
    let notebookID: UUID?
    let pageID: UUID?

    @State private var destination: ImportDestination
    @State private var showingFileImporter = false
    @State private var pickedURLs: [URL] = []
    @State private var isImporting = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

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
        _destination = State(initialValue: initialDestination)
    }

    private var allowedTypes: [UTType] {
        var types: [UTType] = [.pdf, .image, .audio, .plainText]
        let extensions = ["epub", "ppt", "pptx", "doc", "docx", "md", "markdown"]
        for fileExtension in extensions {
            if let type = UTType(filenameExtension: fileExtension), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("导入文件")
                        .font(FNTheme.serif(28, weight: .semibold))
                        .foregroundStyle(FNTheme.ink)
                    Text("文件会复制到 FreeNote 沙盒，原文件保持不变。")
                        .font(.system(size: 12))
                        .foregroundStyle(FNTheme.secondaryInk)
                }
                Spacer()
                FNIconButton(symbol: "xmark") { dismiss() }
            }

            Button {
                showingFileImporter = true
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(FNTheme.accent)
                    Text(pickedURLs.isEmpty ? "从“文件”选择" : "已选择 \(pickedURLs.count) 个文件")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FNTheme.ink)
                    Text(pickedURLs.isEmpty ? "支持 PDF、EPUB、PPT、Word、图片、音频和文本" : pickedURLs.map(\.lastPathComponent).joined(separator: "、"))
                        .font(.system(size: 10))
                        .foregroundStyle(FNTheme.tertiaryInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .background(FNTheme.accentSoft.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(FNTheme.accent.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                )
            }
            .buttonStyle(.plain)

            HStack(spacing: 7) {
                ForEach(["PDF", "Word / PPT", "EPUB", "图片", "音频"], id: \.self) { type in
                    Text(type)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(FNTheme.secondaryInk)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(FNTheme.sidebar)
                        .clipShape(Capsule())
                }
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
                    subtitle: "适合图片、音频和零散资料",
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

            Spacer(minLength: 0)

            HStack {
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在复制并识别文件…")
                        .font(.system(size: 10))
                        .foregroundStyle(FNTheme.secondaryInk)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                Button("开始导入", action: startImport)
                    .buttonStyle(.borderedProminent)
                    .tint(FNTheme.accent)
                    .disabled(pickedURLs.isEmpty || isImporting)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 600)
        .background(FNTheme.contentBackground)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                pickedURLs = urls
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("导入完成", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("好") {
                resultMessage = nil
                dismiss()
            }
        } message: {
            Text(resultMessage ?? "")
        }
        .alert("导入失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func destinationRow(_ value: ImportDestination, title: String, subtitle: String, symbol: String) -> some View {
        Button {
            destination = value
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(destination == value ? FNTheme.accent : FNTheme.secondaryInk)
                    .frame(width: 34, height: 34)
                    .background(destination == value ? FNTheme.accentSoft : FNTheme.sidebar)
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
                Image(systemName: destination == value ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(destination == value ? FNTheme.accent : FNTheme.tertiaryInk)
            }
            .padding(11)
            .background(destination == value ? FNTheme.accentSoft.opacity(0.52) : FNTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(destination == value ? FNTheme.accent.opacity(0.35) : FNTheme.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func startImport() {
        guard !pickedURLs.isEmpty else { return }
        isImporting = true
        Task {
            let results: [ImportResult]
            if destination == .currentPage, let notebookID, let pageID {
                results = await store.importFiles(pickedURLs, notebookID: notebookID, pageID: pageID)
            } else if destination == .currentPage {
                isImporting = false
                errorMessage = "当前页面信息已失效，请重新打开笔记后再导入。"
                return
            } else {
                results = await store.importFiles(pickedURLs, destination: destination)
            }

            isImporting = false
            let succeeded = results.filter(\.success).count
            let failed = results.filter { !$0.success }
            let warnings = results.compactMap(\.warningMessage)
            let warningText = warnings.isEmpty ? "" : "\n\n目录识别提示：\n" + warnings.prefix(5).joined(separator: "\n")
            if failed.isEmpty {
                resultMessage = "已成功导入 \(succeeded) 个文件。\(warningText)"
            } else {
                let details = failed.prefix(3).map { item in
                    "\(item.title)：\(item.errorMessage ?? "未知错误")"
                }.joined(separator: "\n")
                resultMessage = "成功 \(succeeded) 个，失败 \(failed.count) 个。\n\(details)\(warningText)"
            }
        }
    }
}
