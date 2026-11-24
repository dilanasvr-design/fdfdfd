import SwiftUI

/// Draws a chess move arrow (from-square → to-square) over the board preview.
/// Coordinates are relative to the Canvas's own size, which must match the
/// displayed image size. The boardRect is in image-pixel space; we scale it.
struct ArrowOverlayView: View {
    let move: ChessMove
    let boardRect: CGRect   // in image-pixel coordinates

    // Arrow style
    private let bodyWidth: CGFloat = 6
    private let shadowWidth: CGFloat = 9
    private let headLength: CGFloat = 22
    private let headAngle: CGFloat = .pi / 5   // 36°
    private let arrowColor: Color = .yellow
    private let shadowColor: Color = Color.black.opacity(0.55)

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                guard
                    let from = squareCenter(notation: move.from, canvasSize: size),
                    let to   = squareCenter(notation: move.to,   canvasSize: size)
                else { return }

                // Shorten the line so it doesn't overlap the arrowhead
                let direction = normalize(CGPoint(x: to.x - from.x, y: to.y - from.y))
                let lineEnd   = CGPoint(
                    x: to.x - direction.x * headLength * 0.6,
                    y: to.y - direction.y * headLength * 0.6
                )

                // Shadow pass
                var shadowPath = Path()
                shadowPath.move(to: from)
                shadowPath.addLine(to: lineEnd)
                ctx.stroke(shadowPath, with: .color(shadowColor),
                           style: StrokeStyle(lineWidth: shadowWidth, lineCap: .round))

                // Body pass
                var bodyPath = Path()
                bodyPath.move(to: from)
                bodyPath.addLine(to: lineEnd)
                ctx.stroke(bodyPath, with: .color(arrowColor),
                           style: StrokeStyle(lineWidth: bodyWidth, lineCap: .round))

                // Arrowhead shadow
                let headShadow = buildHead(tip: to, direction: direction, length: headLength + 2)
                ctx.fill(headShadow, with: .color(shadowColor))

                // Arrowhead fill
                let head = buildHead(tip: to, direction: direction, length: headLength)
                ctx.fill(head, with: .color(arrowColor))

                // Origin dot (from-square indicator)
                let dotRadius: CGFloat = bodyWidth * 1.2
                let dotRect = CGRect(x: from.x - dotRadius, y: from.y - dotRadius,
                                     width: dotRadius * 2, height: dotRadius * 2)
                ctx.fill(Path(ellipseIn: dotRect), with: .color(arrowColor.opacity(0.7)))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Coordinate helpers

    /// Maps algebraic notation ("e2") to a point in canvas coordinates.
    /// boardRect is in image-pixel space; we map it to canvas space using
    /// the ratio of canvas size to the screen bounds of the preview image.
    private func squareCenter(notation: String, canvasSize: CGSize) -> CGPoint? {
        guard notation.count == 2 else { return nil }
        let chars = Array(notation.lowercased())
        guard let fileVal = chars[0].asciiValue,
              let rankVal = chars[1].asciiValue,
              fileVal >= 97, fileVal <= 104,   // a-h
              rankVal >= 49, rankVal <= 56      // 1-8
        else { return nil }

        let file = Int(fileVal - 97)   // 0…7
        let rank = Int(rankVal - 49)   // 0…7

        let squareW = boardRect.width  / 8
        let squareH = boardRect.height / 8

        // boardRect is in image-pixel space; canvas covers the full image
        // as displayed (scaledToFit). We assume the canvas == displayed image.
        let imageW = canvasSize.width
        let imageH = canvasSize.height
        let bW = boardRect.width
        let bH = boardRect.height

        // Scale factors from image pixels → canvas pixels
        // (They're equal for scaledToFit when aspect ratios match; approximate otherwise.)
        let sx = imageW / max(bW / 0.72, 1)   // 0.72 is the board-to-image width ratio
        let sy = imageH / max(bH / 0.72, 1)
        // Simpler: treat the canvas as the full image pixel space (1:1)
        // since Image(..).scaledToFit fills the ZStack with the same aspect ratio.
        let cx = boardRect.minX + CGFloat(file) * squareW + squareW / 2
        let cy = boardRect.minY + CGFloat(7 - rank) * squareH + squareH / 2   // flip Y: rank 1 at bottom

        // Map from image-pixel space to canvas space
        // The canvas GeometryReader gives us the display size; we need the
        // display-to-image scale. We approximate using canvasSize / UIScreen.main.bounds.
        let screenW = UIScreen.main.bounds.width
        let screenH = UIScreen.main.bounds.height
        return CGPoint(x: cx * canvasSize.width / screenW,
                       y: cy * canvasSize.height / screenH)
    }

    private func buildHead(tip: CGPoint, direction: CGPoint, length: CGFloat) -> Path {
        let left = CGPoint(
            x: tip.x - length * (direction.x * cos(headAngle) - direction.y * sin(headAngle)),
            y: tip.y - length * (direction.y * cos(headAngle) + direction.x * sin(headAngle))
        )
        let right = CGPoint(
            x: tip.x - length * (direction.x * cos(-headAngle) - direction.y * sin(-headAngle)),
            y: tip.y - length * (direction.y * cos(-headAngle) + direction.x * sin(-headAngle))
        )
        var path = Path()
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }

    private func normalize(_ p: CGPoint) -> CGPoint {
        let len = sqrt(p.x * p.x + p.y * p.y)
        guard len > 0 else { return .zero }
        return CGPoint(x: p.x / len, y: p.y / len)
    }
}
