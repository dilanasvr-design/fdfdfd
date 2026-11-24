import ReplayKit
import UIKit

/// Wraps RPScreenRecorder to deliver UIImage frames via a callback.
/// The first time `start()` is called iOS shows a system permission prompt.
/// Subsequent calls within the same session skip it.
class ScreenCapture: NSObject, RPScreenRecorderDelegate {
    var onFrame: ((UIImage) -> Void)?

    private let recorder = RPScreenRecorder.shared()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // Rate-limit: skip frames that arrive faster than this interval (seconds)
    private let minInterval: TimeInterval = 0.1
    private var lastDelivered: Date = .distantPast

    override init() {
        super.init()
        recorder.delegate = self
    }

    func start() {
        guard RPScreenRecorder.isAvailable() else {
            print("[ScreenCapture] screen recording not available on this device")
            return
        }
        recorder.isMicrophoneEnabled = false
        recorder.isCameraEnabled     = false

        recorder.startCapture(handler: { [weak self] sampleBuffer, bufferType, error in
            guard let self else { return }
            if let error { print("[ScreenCapture] frame error: \(error)"); return }
            guard bufferType == .video else { return }

            let now = Date()
            guard now.timeIntervalSince(self.lastDelivered) >= self.minInterval else { return }
            self.lastDelivered = now

            guard let image = self.image(from: sampleBuffer) else { return }
            DispatchQueue.main.async { self.onFrame?(image) }

        }, completionHandler: { error in
            if let error { print("[ScreenCapture] start error: \(error)") }
        })
    }

    func stop() {
        recorder.stopCapture { error in
            if let error { print("[ScreenCapture] stop error: \(error)") }
        }
    }

    // MARK: - RPScreenRecorderDelegate

    func screenRecorderDidChangeAvailability(_ screenRecorder: RPScreenRecorder) {
        print("[ScreenCapture] availability changed: \(screenRecorder.isAvailable)")
    }

    func screenRecorder(_ screenRecorder: RPScreenRecorder,
                        didStopRecordingWith previewViewController: RPPreviewViewController?,
                        error: Error?) {
        if let error { print("[ScreenCapture] recording stopped with error: \(error)") }
    }

    // MARK: - Frame conversion

    private func image(from sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
