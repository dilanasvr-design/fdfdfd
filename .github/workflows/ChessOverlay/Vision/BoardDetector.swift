import UIKit
import Vision
import CoreImage

struct ChessSquare {
    let file: Int  // 0 = a-file … 7 = h-file
    let rank: Int  // 0 = rank 1 … 7 = rank 8
    let rect: CGRect
}

/// Locates the chessboard within a screenshot.
///
/// Detection strategy (two-pass):
///  1. Contour detection via Vision to find the largest near-square region.
///  2. Fallback: geometric heuristic based on Chess.com's known layout
///     (board ≈ 72% of the narrower screen dimension, vertically centred).
///
/// For Chess.com on iPhone 15 Pro Max in Safari (portrait), pass 1 is reliable.
/// Other apps / orientations may need the CoreML path — see FENBuilder.swift.
class BoardDetector {

    // MARK: - Public

    func detectBoard(in image: UIImage) -> CGRect? {
        // Try contour detection first; fall back to heuristic.
        return detectViaContours(in: image) ?? heuristicBoard(for: image.size)
    }

    /// Splits the board rect into an 8×8 grid of squares.
    /// Returns [rank-row][file-col], rank-row 0 = rank 8 (top of image, black's back rank when white is at bottom).
    func squares(in boardRect: CGRect, flipped: Bool = false) -> [[ChessSquare]] {
        let size = boardRect.width / 8
        var grid = [[ChessSquare]]()
        for rankRow in 0..<8 {
            var row = [ChessSquare]()
            for fileCol in 0..<8 {
                let rect = CGRect(
                    x: boardRect.minX + CGFloat(fileCol) * size,
                    y: boardRect.minY + CGFloat(rankRow) * size,
                    width: size,
                    height: size
                )
                // If white is at the bottom: rankRow 0 (top) = rank 8, rankRow 7 (bottom) = rank 1
                let rank = flipped ? rankRow : (7 - rankRow)
                row.append(ChessSquare(file: fileCol, rank: rank, rect: rect))
            }
            grid.append(row)
        }
        return grid
    }

    // MARK: - Contour detection

    private func detectViaContours(in image: UIImage) -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 1.5
        request.detectsDarkOnLight = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        guard let results = request.results, !results.isEmpty else { return nil }

        let imageSize = image.size
        var bestRect: CGRect?
        var bestScore: CGFloat = 0

        for observation in results {
            let box = observation.boundingBox   // normalized, origin bottom-left
            // Convert to UIKit coords (origin top-left)
            let rect = CGRect(
                x: box.origin.x * imageSize.width,
                y: (1 - box.origin.y - box.height) * imageSize.height,
                width: box.width * imageSize.width,
                height: box.height * imageSize.height
            )

            // Score: prefer large, square regions
            let aspectRatio = rect.width / max(rect.height, 1)
            let squareness = 1 - abs(aspectRatio - 1)   // 1.0 = perfect square
            let area = rect.width * rect.height
            let minDim = min(imageSize.width, imageSize.height)
            let relativeSizePct = area / (minDim * minDim)

            // Must occupy at least 20% and be reasonably square
            guard relativeSizePct > 0.2, squareness > 0.7 else { continue }

            let score = squareness * relativeSizePct
            if score > bestScore {
                bestScore = score
                bestRect = rect
            }
        }

        // Snap to square (use width as authority)
        if var r = bestRect {
            r = CGRect(x: r.origin.x, y: r.origin.y, width: r.width, height: r.width)
            return r
        }
        return nil
    }

    // MARK: - Heuristic fallback

    private func heuristicBoard(for size: CGSize) -> CGRect {
        // Chess.com Safari portrait on iPhone 15 Pro Max:
        // board fills ~72% of screen width, horizontally centred,
        // top ~38% of screen height.
        let boardSize = min(size.width, size.height) * 0.72
        let x = (size.width - boardSize) / 2
        let y = size.height * 0.18   // tuned for Chess.com portrait
        return CGRect(x: x, y: y, width: boardSize, height: boardSize)
    }
}
