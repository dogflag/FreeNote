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
        let paperColor = UIColor(FNTheme.paperColor(tone: paperTone))
        let lineColor = UIColor(FNTheme.divider)
        contentView.configure(style: paperStyle, paperColor: paperColor, lineColor: lineColor)

        let canvas = PKCanvasView(frame: contentView.bounds)
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = .pencilOnly
        canvas.drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        canvas.tool = tool.makePencilKitTool(color: color, lineWidth: lineWidth)
        canvas.delegate = context.coordinator
        contentView.addSubview(canvas)

        let eraserOverlay = PressureEraserCanvasOverlay(frame: contentView.bounds)
        eraserOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        eraserOverlay.canvasView = canvas
        eraserOverlay.setEraserMode(tool == .eraser, width: lineWidth)
        contentView.addSubview(eraserOverlay)
        context.coordinator.eraserOverlay = eraserOverlay

        scrollView.addSubview(contentView)
        scrollView.contentSize = Self.contentSize

        context.coordinator.contentView = contentView
        context.coordinator.canvasView = canvas
        context.coordinator.lastAppliedData = drawingData
        context.coordinator.lastPaperKey = paperKey(style: paperStyle, tone: paperTone, traits: scrollView.traitCollection)

        controller.canvasView = canvas
        controller.navigationScrollView = scrollView

        DispatchQueue.main.async {
            scrollView.setZoomScale(0.62, animated: false)
            controller.recenter(animated: false)
            controller.updateZoomScale(scrollView.zoomScale)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        guard let canvas = context.coordinator.canvasView,
              let contentView = context.coordinator.contentView else { return }

        context.coordinator.eraserOverlay?.setEraserMode(tool == .eraser, width: lineWidth)
        controller.canvasView = canvas
        controller.navigationScrollView = scrollView
        scrollView.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        canvas.drawingPolicy = .pencilOnly
        canvas.tool = tool.makePencilKitTool(color: color, lineWidth: lineWidth)

        let key = paperKey(style: paperStyle, tone: paperTone, traits: scrollView.traitCollection)
        if context.coordinator.lastPaperKey != key {
            contentView.configure(
                style: paperStyle,
                paperColor: UIColor(FNTheme.paperColor(tone: paperTone)),
                lineColor: UIColor(FNTheme.divider)
            )
            context.coordinator.lastPaperKey = key
        }

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

    private func paperKey(style: PaperStyle, tone: String, traits: UITraitCollection) -> String {
        "\(style.rawValue)-\(tone)-\(traits.userInterfaceStyle.rawValue)"
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate {
        var parent: InfinitePencilCanvasView
        fileprivate weak var contentView: PaperTiledContentView?
        weak var canvasView: PKCanvasView?
        weak var eraserOverlay: PressureEraserCanvasOverlay?
        var lastAppliedData = Data()
        var lastPaperKey = ""
        var isApplyingExternalDrawing = false

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
            let data = canvasView.drawing.dataRepresentation()
            lastAppliedData = data
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


