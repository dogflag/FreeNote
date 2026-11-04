import SwiftUI
import PencilKit
import UIKit

enum DrawingTool: String, CaseIterable, Identifiable {
    case pen
    case highlighter
    case eraser
    case lasso

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: return "钢笔"
        case .highlighter: return "荧光笔"
        case .eraser: return "橡皮"
        case .lasso: return "套索"
        }
    }

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        case .lasso: return "lasso"
        }
    }
}

final class PencilCanvasController: ObservableObject {
    weak var canvasView: PKCanvasView?

    func undo() {
        canvasView?.undoManager?.undo()
    }

    func redo() {
        canvasView?.undoManager?.redo()
    }

    var canUndo: Bool {
        canvasView?.undoManager?.canUndo ?? false
    }

    var canRedo: Bool {
        canvasView?.undoManager?.canRedo ?? false
    }

    func clear() {
        guard let canvasView else { return }
        canvasView.drawing = PKDrawing()
        canvasView.delegate?.canvasViewDrawingDidChange?(canvasView)
    }
}

struct PencilCanvasView: UIViewRepresentable {
    let drawingData: Data
    let tool: DrawingTool
    let color: UIColor
    let lineWidth: CGFloat
    let pencilOnly: Bool
    let controller: PencilCanvasController
    let onDrawingChanged: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        canvas.drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        canvas.tool = makeTool()
        canvas.delegate = context.coordinator
        controller.canvasView = canvas
        context.coordinator.lastAppliedData = drawingData
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        controller.canvasView = canvas
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        canvas.tool = makeTool()

        guard context.coordinator.lastAppliedData != drawingData else { return }
        let current = canvas.drawing.dataRepresentation()
        guard current != drawingData else {
            context.coordinator.lastAppliedData = drawingData
            return
        }

        context.coordinator.isApplyingExternalDrawing = true
        canvas.drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        context.coordinator.lastAppliedData = drawingData
        context.coordinator.isApplyingExternalDrawing = false
    }

    private func makeTool() -> PKTool {
        switch tool {
        case .pen:
            return PKInkingTool(.pen, color: color, width: lineWidth)
        case .highlighter:
            return PKInkingTool(.highlighter, color: color.withAlphaComponent(0.45), width: max(lineWidth * 3, 12))
        case .eraser:
            return PKEraserTool(.bitmap, width: max(lineWidth * 3, 14))
        case .lasso:
            return PKLassoTool()
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasView
        var lastAppliedData = Data()
        var isApplyingExternalDrawing = false

        init(parent: PencilCanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingExternalDrawing else { return }
            let data = canvasView.drawing.dataRepresentation()
            lastAppliedData = data
            parent.onDrawingChanged(data)
        }
    }
}
