import UIKit
import Vision
import CoreML

/// Builds a FEN string from a screenshot of a chess board.
///
/// Piece classification pipeline (in order of accuracy):
///  1. CoreML model `PieceClassifier.mlmodel` if present in bundle.
///     Train on lichess-org/chess-dataset (HuggingFace) or any labelled
///     piece-square image set. Input: 64×64 RGB square crop.
///     Output: class label one of "P","N","B","R","Q","K","p","n","b","r","q","k","."
///  2. Brightness + saturation heuristic — detects occupied vs empty squares
///     and distinguishes white/black by relative pixel brightness.
///     Accuracy: ~70% piece-present, ~0% piece-type. Enough for Stockfish
///     to return *a* move; not enough for a full position.
///
/// Replace the `classifySquare` body with model inference to hit >95% accuracy.
class FENBuilder {
    private let detector = BoardDetector()
    private var classifier: VNCoreMLModel? = {
        // Load PieceClassifier.mlmodel if bundled
        guard let url = Bundle.main.url(forResource: "PieceClassifier", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: url),
              let vnModel = try? VNCoreMLModel(for: model) else { return nil }
        return vnModel
    }()

    // Active-color tracking: flip on every call, reset on stopCapture.
    // Real solution: detect whose clock is running via OCR on the timer.
    private var moveCount = 0

    func reset() { moveCount = 0 }

    /// Returns (fen, boardRect) or nil if the board can't be located.
    func buildFEN(from image: UIImage) -> (fen: String, boardRect: CGRect)? {
        guard let boardRect = detector.detectBoard(in: image) else { return nil }
        let grid = detector.squares(in: boardRect, flipped: false)

        var rankStrings = [String]()

        for rankRow in grid {
            var rankStr = ""
            var emptyCount = 0

            for square in rankRow {
                let piece = classifySquare(square, in: image)
                if piece == "." {
                    emptyCount += 1
                } else {
                    if emptyCount > 0 {
                        rankStr += "\(emptyCount)"
                        emptyCount = 0
                    }
                    rankStr += piece
                }
            }
            if emptyCount > 0 { rankStr += "\(emptyCount)" }
            rankStrings.append(rankStr)
        }

        moveCount += 1
        // Active colour heuristic: white moves on even calls
        let activeColor = moveCount % 2 == 1 ? "w" : "b"
        // Castling / en-passant unknown from a single frame; assume full rights
        let fen = rankStrings.joined(separator: "/") + " \(activeColor) KQkq - 0 1"
        return (fen, boardRect)
    }

    // MARK: - Square classifier

    private func classifySquare(_ square: ChessSquare, in image: UIImage) -> String {
        guard let cgImage = image.cgImage else { return "." }

        // Crop the square from the full screenshot
        let scale = CGFloat(cgImage.width) / image.size.width
        let scaledRect = CGRect(
            x: square.rect.origin.x * scale,
            y: square.rect.origin.y * scale,
            width: square.rect.width * scale,
            height: square.rect.height * scale
        )
        guard let cropped = cgImage.cropping(to: scaledRect) else { return "." }

        // --- CoreML path (accurate) ---
        if let model = classifier {
            return classifyWithModel(model, cgImage: cropped, square: square)
        }

        // --- Heuristic path (structural placeholder) ---
        return classifyHeuristic(cgImage: cropped, square: square)
    }

    private func classifyWithModel(_ model: VNCoreMLModel, cgImage: CGImage, square: ChessSquare) -> String {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        guard let result = request.results?.first as? VNClassificationObservation,
              result.confidence > 0.5 else { return "." }
        return result.identifier   // expects "P","N","B","R","Q","K","p"... or "."
    }

    private func classifyHeuristic(cgImage: CGImage, square: ChessSquare) -> String {
        // Measure brightness and variance of the centre 50% of the square crop.
        // High variance → piece present (pieces have more contrast than bare squares).
        // Low brightness → dark piece candidate; high brightness → light piece candidate.
        // This is structural scaffolding — it cannot distinguish piece types.
        // Replace with PieceClassifier.mlmodel for real accuracy.

        let (brightness, variance) = pixelStats(of: cgImage)

        // Chess.com light squares: ~0.75-0.85 brightness, low variance
        // Chess.com dark squares:  ~0.45-0.55 brightness, low variance
        // Pieces add significant local variance (edges, shadows)
        let piecePresent = variance > 0.015

        if !piecePresent { return "." }

        // Can't determine piece type without a model.
        // Return a pawn as a placeholder so Stockfish at least gets a non-empty position.
        // accuracy of full position: low; accuracy of "something is here": moderate.
        return brightness > 0.6 ? "P" : "p"
    }

    // MARK: - Pixel utilities

    private func pixelStats(of image: CGImage) -> (brightness: CGFloat, variance: CGFloat) {
        let w = image.width
        let h = image.height
        // Sample centre 50%
        let inset = Int(Double(min(w, h)) * 0.25)
        let x0 = inset, y0 = inset
        let x1 = w - inset, y1 = h - inset

        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return (0, 0) }

        let bytesPerRow = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8

        var sum: CGFloat = 0
        var sumSq: CGFloat = 0
        var count: CGFloat = 0

        for y in y0..<y1 {
            for x in x0..<x1 {
                let offset = y * bytesPerRow + x * bpp
                let r = CGFloat(bytes[offset]) / 255
                let g = CGFloat(bytes[offset + 1]) / 255
                let b = CGFloat(bytes[offset + 2]) / 255
                let luma = r * 0.299 + g * 0.587 + b * 0.114
                sum += luma
                sumSq += luma * luma
                count += 1
            }
        }

        guard count > 0 else { return (0, 0) }
        let mean = sum / count
        let variance = (sumSq / count) - (mean * mean)
        return (mean, variance)
    }
}
