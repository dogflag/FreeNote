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
    weak var navigationScrollView: UIScrollView?
    @Published private(set) var zoomScale: CGFloat = 1.0
    private(set) var hasUnflushedDrawingChanges = false

    var currentDrawingData: Data? {
        canvasView?.drawing.dataRepresentation()
    }

    func markDrawingChanged() {
        hasUnflushedDrawingChanges = true
    }

    func markDrawingFlushed() {
        hasUnflushedDrawingChanges = false
    }

    private var activeUndoManager: UndoManager? {
        canvasView?.undoManager ?? canvasView?.window?.undoManager
    }

    func undo() {
        activeUndoManager?.undo()
    }

    func redo() {
        activeUndoManager?.redo()
    }

    var canUndo: Bool {
        activeUndoManager?.canUndo ?? false
    }

    var canRedo: Bool {
        activeUndoManager?.canRedo ?? false
    }

    func clear() {
        clearWithUndo()
    }

    func clearWithUndo() {
        guard let canvasView, !canvasView.drawing.strokes.isEmpty else { return }
        let previousDrawing = canvasView.drawing
        let undoManager = canvasView.undoManager ?? canvasView.window?.undoManager
        undoManager?.beginUndoGrouping()
        undoManager?.registerUndo(withTarget: self) { target in
            target.restoreDrawing(previousDrawing, on: canvasView)
        }
        undoManager?.setActionName("清空画布")
        undoManager?.disableUndoRegistration()
        canvasView.drawing = PKDrawing()
        undoManager?.enableUndoRegistration()
        undoManager?.endUndoGrouping()
        canvasView.delegate?.canvasViewDrawingDidChange?(canvasView)
    }

    private func restoreDrawing(_ drawing: PKDrawing, on canvasView: PKCanvasView) {
        let previousDrawing = canvasView.drawing
        canvasView.undoManager?.registerUndo(withTarget: self) { target in
            target.restoreDrawing(previousDrawing, on: canvasView)
        }
        canvasView.undoManager?.setActionName("清空画布")
        canvasView.undoManager?.disableUndoRegistration()
        canvasView.drawing = drawing
        canvasView.undoManager?.enableUndoRegistration()
        canvasView.delegate?.canvasViewDrawingDidChange?(canvasView)
    }

    func zoomIn() {
        setZoom((navigationScrollView?.zoomScale ?? zoomScale) * 1.2)
    }

    func zoomOut() {
        setZoom((navigationScrollView?.zoomScale ?? zoomScale) / 1.2)
    }

    func recenter(animated: Bool = true) {
        guard let scrollView = navigationScrollView else { return }
        let drawingBounds = canvasView?.drawing.bounds ?? .null
        let target: CGPoint
        if !drawingBounds.isNull, !drawingBounds.isEmpty {
            target = CGPoint(x: drawingBounds.midX, y: drawingBounds.midY)
        } else {
            let canvasSize = canvasView?.bounds.size ?? scrollView.contentSize
            target = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        }
        let x = max(target.x * scrollView.zoomScale - scrollView.bounds.width / 2, 0)
        let y = max(target.y * scrollView.zoomScale - scrollView.bounds.height / 2, 0)
        scrollView.setContentOffset(CGPoint(x: x, y: y), animated: animated)
    }

    func updateZoomScale(_ value: CGFloat) {
        zoomScale = value
    }

    private func setZoom(_ value: CGFloat) {
        guard let scrollView = navigationScrollView else { return }
        let bounded = min(max(value, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        scrollView.setZoomScale(bounded, animated: true)
        zoomScale = bounded
    }
}

private final class PencilSnapshotLongPressRecognizer: UILongPressGestureRecognizer {
    var onPencilDown: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if touches.contains(where: { $0.type == .pencil }) {
            onPencilDown?()
        }
        super.touchesBegan(touches, with: event)
    }
}

final class PencilTemporaryEraserController: NSObject, UIGestureRecognizerDelegate {
    private weak var canvasView: PKCanvasView?
    private var normalTool: PKTool
    private var normalToolKey: String
    private var toolBeforeTemporaryEraser: PKTool?
    private var drawingAtPencilDown: PKDrawing?

    init(canvasView: PKCanvasView, normalTool: PKTool, normalToolKey: String) {
        self.canvasView = canvasView
        self.normalTool = normalTool
        self.normalToolKey = normalToolKey
        super.init()

        let recognizer = PencilSnapshotLongPressRecognizer(target: self, action: #selector(handleLongPress(_:)))
        recognizer.minimumPressDuration = 0.36
        recognizer.numberOfTouchesRequired = 1
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delegate = self
        recognizer.onPencilDown = { [weak self, weak canvasView] in
            guard let self, let canvasView, self.toolBeforeTemporaryEraser == nil else { return }
            self.drawingAtPencilDown = canvasView.drawing
        }
        canvasView.addGestureRecognizer(recognizer)
    }

    func updateNormalTool(_ tool: PKTool, key: String) {
        guard normalToolKey != key else { return }
        normalToolKey = key
        normalTool = tool
        if toolBeforeTemporaryEraser == nil {
            canvasView?.tool = tool
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.type == .pencil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard let canvasView else { return }
        switch recognizer.state {
        case .began:
            toolBeforeTemporaryEraser = canvasView.tool
            if let snapshot = drawingAtPencilDown {
                restoreSnapshot(snapshot, on: canvasView)
            }
            drawingAtPencilDown = nil
            canvasView.tool = PKEraserTool(.bitmap)
        case .ended, .cancelled, .failed:
            if let previousTool = toolBeforeTemporaryEraser {
                canvasView.tool = previousTool
            } else {
                canvasView.tool = normalTool
            }
            toolBeforeTemporaryEraser = nil
            drawingAtPencilDown = nil
        default:
            break
        }
    }

    private func restoreSnapshot(_ snapshot: PKDrawing, on canvasView: PKCanvasView) {
        let undoManager = canvasView.undoManager ?? canvasView.window?.undoManager
        undoManager?.disableUndoRegistration()
        canvasView.drawing = snapshot
        undoManager?.enableUndoRegistration()
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

        let toolKey = makeToolKey()
        let initialTool = makeTool()
        canvas.tool = initialTool
        canvas.delegate = context.coordinator

        context.coordinator.canvasView = canvas
        context.coordinator.lastAppliedData = drawingData
        context.coordinator.lastToolKey = toolKey
        context.coordinator.temporaryEraser = PencilTemporaryEraserController(
            canvasView: canvas,
            normalTool: initialTool,
            normalToolKey: toolKey
        )

        controller.canvasView = canvas
        controller.navigationScrollView = nil
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        controller.canvasView = canvas
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput

        let toolKey = makeToolKey()
        if context.coordinator.lastToolKey != toolKey {
            let updatedTool = makeTool()
            context.coordinator.lastToolKey = toolKey
            canvas.tool = updatedTool
            context.coordinator.temporaryEraser?.updateNormalTool(updatedTool, key: toolKey)
        }

        guard !context.coordinator.hasLocalCanvasChanges else { return }
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

    static func dismantleUIView(_ canvasView: PKCanvasView, coordinator: Coordinator) {
        coordinator.cancelDebouncedCallback()
        canvasView.delegate = nil
    }

    private func makeTool() -> PKTool {
        tool.makePencilKitTool(color: color, lineWidth: lineWidth)
    }

    private func makeToolKey() -> String {
        "\(tool.rawValue)-\(color.description)-\(lineWidth)"
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasView
        weak var canvasView: PKCanvasView?
        var lastAppliedData = Data()
        var lastToolKey = ""
        var isApplyingExternalDrawing = false
        var hasLocalCanvasChanges = false
        var temporaryEraser: PencilTemporaryEraserController?
        private var debounceWorkItem: DispatchWorkItem?

        init(parent: PencilCanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingExternalDrawing else { return }
            hasLocalCanvasChanges = true
            parent.controller.markDrawingChanged()
            debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak canvasView] in
                guard let self, let canvasView else { return }
                self.emitLatestDrawing(from: canvasView)
            }
            debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        }

        func cancelDebouncedCallback() {
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
        }

        private func emitLatestDrawing(from canvasView: PKCanvasView) {
            let data = canvasView.drawing.dataRepresentation()
            lastAppliedData = data
            hasLocalCanvasChanges = false
            parent.controller.markDrawingFlushed()
            parent.onDrawingChanged(data)
        }
    }
}

extension DrawingTool {
    func makePencilKitTool(color: UIColor, lineWidth: CGFloat) -> PKTool {
        switch self {
        case .pen:
            return PKInkingTool(.pen, color: color, width: lineWidth)
        case .highlighter:
            return PKInkingTool(.marker, color: color.withAlphaComponent(0.42), width: max(lineWidth * 3, 12))
        case .eraser:
            if #available(iOS 16.4, *) {
                return PKEraserTool(.bitmap, width: max(lineWidth * 3, 14))
            } else {
                return PKEraserTool(.bitmap)
            }
        case .lasso:
            return PKLassoTool()
        }
    }
}
