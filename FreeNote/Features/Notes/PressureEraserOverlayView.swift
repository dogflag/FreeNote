import UIKit
import PencilKit

final class PressureEraserCanvasOverlay: UIView {
    weak var canvasView: PKCanvasView?
    private var baseWidth: CGFloat = 8
    private var originalDrawing: PKDrawing?
    private var didEraseInGesture = false
    private var eraserRecognizer: PressureEraserTouchRecognizer!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isHidden = true
        isUserInteractionEnabled = false
        isMultipleTouchEnabled = false

        eraserRecognizer = PressureEraserTouchRecognizer(target: self, action: #selector(handleEraser(_:)))
        eraserRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        eraserRecognizer.cancelsTouchesInView = true
        addGestureRecognizer(eraserRecognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setEraserMode(_ enabled: Bool, width: CGFloat) {
        baseWidth = max(width, 1)
        isHidden = !enabled
        isUserInteractionEnabled = enabled
        if !enabled {
            originalDrawing = nil
            didEraseInGesture = false
        }
    }

    @objc private func handleEraser(_ recognizer: PressureEraserTouchRecognizer) {
        guard let canvasView, let touch = recognizer.activeTouch else { return }
        switch recognizer.state {
        case .began:
            originalDrawing = canvasView.drawing
            didEraseInGesture = false
            erase(at: touch, in: canvasView)
        case .changed:
            erase(at: touch, in: canvasView)
        case .ended, .cancelled:
            erase(at: touch, in: canvasView)
            registerSingleUndo(for: canvasView)
        default:
            break
        }
    }

    private func erase(at touch: UITouch, in canvasView: PKCanvasView) {
        let point = touch.location(in: canvasView)
        let normalizedForce: CGFloat
        if touch.maximumPossibleForce > 0 {
            normalizedForce = min(max(touch.force / touch.maximumPossibleForce, 0.04), 1)
        } else {
            normalizedForce = touch.force > 0 ? 0.7 : 0.28
        }
        let radius = max(baseWidth * 0.45, 3) * (0.7 + normalizedForce * 2.3)
        let currentDrawing = canvasView.drawing
        let remainingStrokes = currentDrawing.strokes.filter { stroke in
            !strokeIntersects(stroke, point: point, radius: radius)
        }
        guard remainingStrokes.count != currentDrawing.strokes.count else { return }

        canvasView.undoManager?.disableUndoRegistration()
        canvasView.drawing = PKDrawing(strokes: remainingStrokes)
        canvasView.undoManager?.enableUndoRegistration()
        canvasView.delegate?.canvasViewDrawingDidChange?(canvasView)
        didEraseInGesture = true
    }

    private func strokeIntersects(_ stroke: PKStroke, point: CGPoint, radius: CGFloat) -> Bool {
        guard stroke.renderBounds.insetBy(dx: -radius, dy: -radius).contains(point) else {
            return false
        }
        for index in 0..<stroke.path.count {
            let strokePoint = stroke.path.point(at: index)
            let halfWidth = max(strokePoint.size.width, strokePoint.size.height) * 0.5
            let threshold = radius + halfWidth
            let dx = strokePoint.location.x - point.x
            let dy = strokePoint.location.y - point.y
            if dx * dx + dy * dy <= threshold * threshold {
                return true
            }
        }
        return false
    }

    private func registerSingleUndo(for canvasView: PKCanvasView) {
        defer {
            originalDrawing = nil
            didEraseInGesture = false
        }
        guard didEraseInGesture, let originalDrawing else { return }
        let undoManager = canvasView.undoManager ?? canvasView.window?.undoManager
        undoManager?.registerUndo(withTarget: self) { target in
            target.restoreDrawing(originalDrawing)
        }
        undoManager?.setActionName("压力擦除")
    }

    private func restoreDrawing(_ drawing: PKDrawing) {
        guard let canvasView else { return }
        let previousDrawing = canvasView.drawing
        let undoManager = canvasView.undoManager ?? canvasView.window?.undoManager
        undoManager?.registerUndo(withTarget: self) { target in
            target.restoreDrawing(previousDrawing)
        }
        undoManager?.setActionName("压力擦除")
        undoManager?.disableUndoRegistration()
        canvasView.drawing = drawing
        undoManager?.enableUndoRegistration()
        canvasView.delegate?.canvasViewDrawingDidChange?(canvasView)
    }
}

private final class PressureEraserTouchRecognizer: UIGestureRecognizer {
    private(set) var activeTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard activeTouch == nil,
              let touch = touches.first(where: { $0.type == .pencil }) else {
            state = .failed
            return
        }
        activeTouch = touch
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let activeTouch, touches.contains(activeTouch) else {
            state = .failed
            return
        }
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    override func reset() {
        activeTouch = nil
        super.reset()
    }
}
