import SwiftUI
import ReplayKit

struct ContentView: View {
    @StateObject private var engine = ChessEngine()
    @State private var isCapturing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Text("♟ Chess Overlay")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text(engine.status)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                ZStack {
                    if let frame = engine.latestFrame {
                        Image(uiImage: frame)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(8)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 300)
                            .overlay(
                                Text("Screen preview appears here")
                                    .foregroundColor(.gray)
                            )
                    }

                    if let move = engine.bestMove, let rect = engine.boardRect {
                        ArrowOverlayView(move: move, boardRect: rect)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)

                if let move = engine.bestMove {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.green)
                        Text("Best move: \(move.from.uppercased()) → \(move.to.uppercased())")
                            .font(.title2)
                            .foregroundColor(.green)
                            .bold()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(10)
                }

                Button(action: { isCapturing ? stopCapture() : startCapture() }) {
                    HStack {
                        Image(systemName: isCapturing ? "stop.circle.fill" : "play.circle.fill")
                        Text(isCapturing ? "Stop Capture" : "Start Capture")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isCapturing ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .font(.headline)
                }
                .padding(.horizontal)

                Text("Run Chess.com in Safari alongside this app.\nThis app reads your screen and shows the best move.")
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.vertical, 40)
        }
    }

    func startCapture() {
        isCapturing = true
        engine.startCapture()
    }

    func stopCapture() {
        isCapturing = false
        engine.stopCapture()
    }
}
