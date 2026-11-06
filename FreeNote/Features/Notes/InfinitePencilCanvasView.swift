import SwiftUI
import PencilKit
import UIKit

struct InfinitePencilCanvasView: UIViewRepresentable {
    static let contentSize = CGSize(width: 5200, height: 4200)

    let drawingData: Data
    let tool: DrawingTool
    let color: UIColor
    let lineWidth: CGFloat
    let paperStyle: PaperStyle
    let paperTone: String
    let controller: PencilCanvasController
    let onDrawingChanged: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = UIColor(FNTheme.appBackground)
        scrollView.minimumZoomScale = 0.28
        scrollView.maximumZoomScale = 2.5
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]

        let contentView = PaperTiledContentView(
            frame: CGRect(origin: .zero, size: Self.contentSize)
        )
        contentView.configure(
            style: paperStyle,
            paperColor: UIColor(FNTheme.paperColor(tone: paperTone)),
            lineColor: UIColor(FNTheme.paperLine)
        )

        let canvas = PKCanvasView(frame: contentView.bounds)
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = .pencilOnly
        canvas.drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        let toolKey = makeToolKey()
        let initialTool = makeTool()
        canvas.tool = initialTool
        canvas.delegate = context.coordinator
        contentView.addSubview(canvas)

        scrollView.addSubview(contentView)
        scrollView.contentSize = Self.contentSize

        context.coordinator.contentView = contentView
        context.coordinator.canvasView = canvas
        context.coordinator.lastAppliedData = drawingData
        context.coordinator.lastToolKey = toolKey
        context.coordinator.lastPaperKey = paperKey(
            style: paperStyle,
            tone: paperTone,
            traits: scrollView.traitCollection
        )
        context.coordinator.temporaryEraser = PencilTemporaryEraserController(
            canvasView: canvas,
            normalTool: initialTool,
            normalToolKey: toolKey
        )

        controller.canvasView = canvas
        controller.navigationScrollView = scrollView

        DispatchQueue.main.async {
            scrollView.setZoomScale(1.0, animated: false)
            controller.recenter(animated: false)
            controller.updateZoomScale(scrollView.zoomScale)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        guard let canvas = context.coordinator.canvasView,
              let contentView = context.coordinator.contentView else { return }

        controller.canvasView = canvas
        controller.navigationScrollView = scrollView
        scrollView.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        canvas.drawingPolicy = .pencilOnly

        let toolKey = makeToolKey()
        if context.coordinator.lastToolKey != toolKey {
            let updatedTool = makeTool()
            context.coordinator.lastToolKey = toolKey
            canvas.tool = updatedTool
            context.coordinator.temporaryEraser?.updateNormalTool(updatedTool, key: toolKey)
        }

        let key = paperKey(
            style: paperStyle,
            tone: paperTone,
            traits: scrollView.traitCollection
        )
        if context.coordinator.lastPaperKey != key {
            contentView.configure(
                style: paperStyle,
                paperColor: UIColor(FNTheme.paperColor(tone: paperTone)),
                lineColor: UIColor(FNTheme.paperLine)
            )
            context.coordinator.lastPaperKey = key
        }

        guard !context.coordinator.hasLocalCanvasChanges else { return }
        guard context.coordinator.lastAppliedData != drawingData else { return }
        let current = canvas.drawing.dataRepresentation()
        if current == drawingData {
            context.coordinator.lastAppliedData = drawingData
            return
        }
        context.coordinator.isApplyingExternalDrawing = true
        canvas.drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        context.coordinator.lastAppliedData = drawingData
        context.coordinator.isApplyingExternalDrawing = false
    }

    static func dismantleUIView(_ scrollView: UIScrollView, coordinator: Coordinator) {
        coordinator.cancelDebouncedCallback()
        coordinator.canvasView?.delegate = nil
    }

    private func makeTool() -> PKTool {
        tool.makePencilKitTool(color: color, lineWidth: lineWidth)
    }

    private func makeToolKey() -> String {
        "\(tool.rawValue)-\(color.description)-\(lineWidth)"
    }

    private func paperKey(style: PaperStyle, tone: String, traits: UITraitCollection) -> String {
        "\(style.rawValue)-\(tone)-\(traits.userInterfaceStyle.rawValue)"
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate {
        var parent: InfinitePencilCanvasView
        fileprivate weak var contentView: PaperTiledContentView?
        weak var canvasView: PKCanvasView?
        var lastAppliedData = Data()
        var lastToolKey = ""
        var lastPaperKey = ""
        var isApplyingExternalDrawing = false
        var hasLocalCanvasChanges = false
        var temporaryEraser: PencilTemporaryEraserController?
        private var debounceWorkItem: DispatchWorkItem?

        init(parent: InfinitePencilCanvasView) {
            self.parent = parent
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            contentView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            parent.controller.updateZoomScale(scrollView.zoomScale)
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

fileprivate final class PaperTiledContentView: UIView {
    private var currentStyle: PaperStyle = .blank
    private var currentPaperColor = UIColor.white
    private var currentLineColor = UIColor.lightGray

    func configure(style: PaperStyle, paperColor: UIColor, lineColor: UIColor) {
        currentStyle = style
        currentPaperColor = paperColor
        currentLineColor = lineColor
        applyPattern()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            applyPattern()
        }
    }

    private func applyPattern() {
        guard currentStyle != .blank else {
            backgroundColor = currentPaperColor
            return
        }

        let tileSize = CGSize(width: 32, height: 32)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: tileSize, format: format)
        let tile = renderer.image { context in
            currentPaperColor.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: tileSize))

            currentLineColor.setStroke()
            let path = UIBezierPath()
            switch currentStyle {
            case .blank:
                break
            case .lined:
                path.move(to: CGPoint(x: 0, y: 31.5))
                path.addLine(to: CGPoint(x: 32, y: 31.5))
            case .grid:
                path.move(to: CGPoint(x: 0, y: 31.5))
                path.addLine(to: CGPoint(x: 32, y: 31.5))
                path.move(to: CGPoint(x: 31.5, y: 0))
                path.addLine(to: CGPoint(x: 31.5, y: 32))
            case .dotted:
                currentLineColor.setFill()
                UIBezierPath(ovalIn: CGRect(x: 15, y: 15, width: 2, height: 2)).fill()
            }
            path.lineWidth = 0.7
            path.stroke()
        }
        backgroundColor = UIColor(patternImage: tile)
    }
}
