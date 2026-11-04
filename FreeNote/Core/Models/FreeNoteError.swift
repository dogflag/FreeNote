import Foundation

enum FreeNoteError: Error, LocalizedError, Equatable {
    case notebookNotFound(UUID)
    case pageNotFound(UUID)
    case drawingFileMissing(UUID)
    case bookNotFound(UUID)
    case resourceNotFound(UUID)
    case duplicatePageID(UUID)
    case duplicateOutlineNodeID(UUID)
    case invalidOutlineRange(nodeID: UUID, startPage: Int, endPage: Int)
    case outlinePageOutOfBounds(nodeID: UUID, startPage: Int, endPage: Int, pageCount: Int)
    case outlineNodeNotFound(UUID)
    case outlineParentNotFound(UUID)
    case invalidOutlineMove
    case cannotDeleteLastPage(UUID)
    case importSourceUnreadable(String)
    case documentHasNoReadablePages(String)
    case persistenceFailed(String)
    case fileOperationFailed(String)
    case invalidState(String)

    var errorDescription: String? {
        switch self {
        case .notebookNotFound:
            return "找不到指定的笔记。"
        case .pageNotFound:
            return "找不到指定的页面。"
        case .drawingFileMissing:
            return "页面的手写文件不存在，不能将其视为空白画布并覆盖。"
        case .bookNotFound:
            return "找不到指定的书籍或文档。"
        case .resourceNotFound:
            return "找不到指定的资源。"
        case .duplicatePageID:
            return "页面标识重复，数据未保存。"
        case .duplicateOutlineNodeID:
            return "大纲节点标识重复，数据未保存。"
        case let .invalidOutlineRange(_, startPage, endPage):
            return "大纲页面范围无效：\(startPage)–\(endPage)。"
        case let .outlinePageOutOfBounds(_, startPage, endPage, pageCount):
            return "大纲页面范围 \(startPage)–\(endPage) 超出文档页数 \(pageCount)。"
        case .outlineNodeNotFound:
            return "找不到指定的大纲节点。"
        case .outlineParentNotFound:
            return "找不到目标大纲节点。"
        case .invalidOutlineMove:
            return "不能将大纲节点移动到自身或自身的子节点中。"
        case .cannotDeleteLastPage:
            return "笔记至少需要保留一页。"
        case let .importSourceUnreadable(name):
            return "无法读取导入文件：\(name)。"
        case let .documentHasNoReadablePages(name):
            return "文档没有可读取的页面，未加入书架：\(name)。"
        case let .persistenceFailed(message):
            return "本地数据保存失败：\(message)"
        case let .fileOperationFailed(message):
            return "文件操作失败：\(message)"
        case let .invalidState(message):
            return "数据状态无效：\(message)"
        }
    }
}
