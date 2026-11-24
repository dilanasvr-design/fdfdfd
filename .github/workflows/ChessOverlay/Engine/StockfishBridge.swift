import Foundation

struct ChessMove {
    let from: String   // algebraic, e.g. "e2"
    let to: String     // algebraic, e.g. "e4"
    let promotion: String?
}

/// Talks to the Stockfish binary bundled in the app via stdin/stdout pipes.
/// Stockfish binary must be compiled for arm64-apple-ios and added to
/// the Xcode target as a Bundle Resource named "stockfish".
/// Build command:
///   cd Stockfish/src
///   make build ARCH=arm64 COMP=clang CXX="xcrun --sdk iphoneos clang++"
///   CXXFLAGS="-target arm64-apple-ios16.0 -isysroot $(xcrun --sdk iphoneos --show-sdk-path)"
class StockfishBridge {
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var ready = false
    private let queue = DispatchQueue(label: "stockfish.io", qos: .userInitiated)

    func start() {
        guard let binaryPath = Bundle.main.path(forResource: "stockfish", ofType: nil) else {
            print("[StockfishBridge] stockfish binary not found in bundle — add it as a Bundle Resource")
            return
        }

        process = Process()
        inputPipe = Pipe()
        outputPipe = Pipe()

        process?.executableURL = URL(fileURLWithPath: binaryPath)
        process?.standardInput = inputPipe
        process?.standardOutput = outputPipe
        process?.standardError = Pipe()   // discard stderr

        do {
            try process?.run()
        } catch {
            print("[StockfishBridge] failed to start: \(error)")
            return
        }

        send("uci")
        send("setoption name Hash value 64")
        send("setoption name Threads value 2")
        send("isready")

        // Drain until readyok
        queue.async { [weak self] in
            self?.waitForReady()
        }
    }

    func stop() {
        send("quit")
        process?.terminate()
        process = nil
        ready = false
    }

    /// Ask Stockfish for the best move in the given FEN at the given depth.
    /// Calls completion on the main thread.
    func bestMove(fen: String, depth: Int = 15, completion: @escaping (ChessMove?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.send("position fen \(fen)")
            self.send("go depth \(depth)")

            let move = self.readBestMove()
            DispatchQueue.main.async { completion(move) }
        }
    }

    // MARK: - Private

    private func waitForReady() {
        guard let handle = outputPipe?.fileHandleForReading else { return }
        while true {
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { continue }
            if text.contains("readyok") {
                ready = true
                return
            }
        }
    }

    private func readBestMove() -> ChessMove? {
        guard let handle = outputPipe?.fileHandleForReading else { return nil }
        var accumulated = ""
        let deadline = Date().addingTimeInterval(10)   // 10s hard timeout

        while Date() < deadline {
            let data = handle.availableData
            if data.isEmpty { Thread.sleep(forTimeInterval: 0.01); continue }
            guard let chunk = String(data: data, encoding: .utf8) else { continue }
            accumulated += chunk

            for line in accumulated.components(separatedBy: "\n") {
                if line.hasPrefix("bestmove") {
                    // bestmove e2e4 ponder d7d5
                    let parts = line.split(separator: " ")
                    guard parts.count >= 2 else { return nil }
                    let mv = String(parts[1])
                    guard mv.count >= 4, mv != "(none)" else { return nil }
                    return ChessMove(
                        from: String(mv.prefix(2)),
                        to: String(mv.dropFirst(2).prefix(2)),
                        promotion: mv.count > 4 ? String(mv.last!) : nil
                    )
                }
            }
        }
        return nil
    }

    private func send(_ cmd: String) {
        guard let pipe = inputPipe else { return }
        let data = (cmd + "\n").data(using: .utf8)!
        pipe.fileHandleForWriting.write(data)
    }
}
