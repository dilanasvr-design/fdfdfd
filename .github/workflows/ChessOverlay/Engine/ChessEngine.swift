import SwiftUI
import Combine

class ChessEngine: ObservableObject {
    @Published var latestFrame: UIImage?
    @Published var bestMove: ChessMove?
    @Published var boardRect: CGRect?
    @Published var status: String = "idle — tap Start Capture"

    private let capture = ScreenCapture()
    private let stockfish = StockfishBridge()
    private let fenBuilder = FENBuilder()
    private var analysing = false
    private var frameCount = 0
    // Only analyse every N frames to avoid hammering CPU
    private let analyseEvery = 15

    init() {
        stockfish.start()
    }

    func startCapture() {
        status = "starting capture..."
        capture.onFrame = { [weak self] frame in
            self?.process(frame: frame)
        }
        capture.start()
    }

    func stopCapture() {
        status = "stopped"
        capture.stop()
        stockfish.stop()
        bestMove = nil
        boardRect = nil
        latestFrame = nil
        analysing = false
        frameCount = 0
    }

    private func process(frame: UIImage) {
        frameCount += 1
        // Show live frame always
        latestFrame = frame

        // Throttle analysis
        guard frameCount % analyseEvery == 0 else { return }
        guard !analysing else { return }
        analysing = true
        status = "detecting board..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let (fen, rect) = self.fenBuilder.buildFEN(from: frame) else {
                DispatchQueue.main.async {
                    self.status = "board not detected — open Chess.com in Safari"
                    self.analysing = false
                }
                return
            }

            DispatchQueue.main.async { self.boardRect = rect }
            DispatchQueue.main.async { self.status = "analysing position (depth 15)..." }

            self.stockfish.bestMove(fen: fen, depth: 15) { [weak self] move in
                guard let self else { return }
                self.bestMove = move
                self.status = move.map { "→ \($0.from.uppercased())\($0.to.uppercased())" } ?? "no move found"
                self.analysing = false
            }
        }
    }
}
