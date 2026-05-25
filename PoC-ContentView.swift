import SwiftUI
import AVFoundation
import Vision
import Combine
import AppKit

struct RecordingResult {
    let minYaw: Double
    let maxYaw: Double
    let faceLost: Bool
    let samples: Int
}

struct ContentView: View {
    @StateObject private var camera = CameraManager()

    var body: some View {
        VStack(spacing: 16) {
            CameraPreview(session: camera.session)
                .frame(height: 240)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(camera.faceDetected ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    Text(camera.faceDetected ? "Face detected" : "No face")
                        .font(.headline)
                }
                Text(String(format: "Yaw:   %+6.1f°", camera.yaw))
                Text(String(format: "Pitch: %+6.1f°", camera.pitch))
                Text(String(format: "Roll:  %+6.1f°", camera.roll))
            }
            .font(.system(.title3, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.gray.opacity(0.12))
            .cornerRadius(8)

            VStack(spacing: 10) {
                if camera.isRecording {
                    Text(String(format: "🔴 Recording... %.1fs", camera.recordingTimeLeft))
                        .font(.title2)
                        .foregroundColor(.red)
                } else {
                    Button(action: { camera.startRecording() }) {
                        Text("▶ Start 5s Recording")
                            .font(.title3)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                    }
                    .keyboardShortcut(.space, modifiers: [])
                }

                Text("Tip: 버튼 클릭 → 삐 소리 → 5초 동안 동작 → 삐 소리 → 화면 확인")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let result = camera.lastResult {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("📊 Last recording")
                            .font(.headline)
                        Text(String(format: "  Min yaw: %+6.1f°", result.minYaw))
                        Text(String(format: "  Max yaw: %+6.1f°", result.maxYaw))
                        Text(String(format: "  Delta:    %5.1f°", result.maxYaw - result.minYaw))
                        Text("  Face lost: \(result.faceLost ? "YES ⚠️" : "no")")
                            .foregroundColor(result.faceLost ? .orange : .primary)
                        Text("  Samples: \(result.samples)")
                            .foregroundColor(.secondary)
                    }
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 720)
    }
}

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.frames")

    @Published var faceDetected = false
    @Published var yaw: Double = 0
    @Published var pitch: Double = 0
    @Published var roll: Double = 0

    @Published var isRecording = false
    @Published var recordingTimeLeft: Double = 0
    @Published var lastResult: RecordingResult?

    private let recordingDuration: Double = 5.0
    private var recordingStart: Date?
    private var recMin: Double?
    private var recMax: Double?
    private var recFaceLost: Bool = false
    private var recSamples: Int = 0

    private var timerCancellable: AnyCancellable?

    override init() {
        super.init()
        configure()
    }

    func startRecording() {
        recMin = nil
        recMax = nil
        recFaceLost = false
        recSamples = 0
        recordingStart = Date()
        isRecording = true
        recordingTimeLeft = recordingDuration
        NSSound.beep()

        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = self.recordingStart else { return }
                let elapsed = Date().timeIntervalSince(start)
                self.recordingTimeLeft = max(0, self.recordingDuration - elapsed)
                if elapsed >= self.recordingDuration {
                    self.finishRecording()
                }
            }
    }

    private func finishRecording() {
        isRecording = false
        timerCancellable?.cancel()
        timerCancellable = nil
        recordingStart = nil
        NSSound.beep()

        let result = RecordingResult(
            minYaw: recMin ?? 0,
            maxYaw: recMax ?? 0,
            faceLost: recFaceLost,
            samples: recSamples
        )
        lastResult = result

        print("=== RECORDING RESULT ===")
        print(String(format: "min=%+.1f° max=%+.1f° delta=%.1f° faceLost=%@ samples=%d",
                     result.minYaw, result.maxYaw,
                     result.maxYaw - result.minYaw,
                     result.faceLost ? "YES" : "no",
                     result.samples))
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            print("[camera] setup failed")
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()

        Task.detached { [session] in
            session.startRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceRectanglesRequest { [weak self] req, _ in
            guard let self else { return }

            guard let face = req.results?.first as? VNFaceObservation else {
                DispatchQueue.main.async {
                    self.faceDetected = false
                    if self.isRecording {
                        self.recFaceLost = true
                    }
                }
                return
            }

            let yaw = (face.yaw?.doubleValue ?? 0) * 180 / .pi
            let pitch = (face.pitch?.doubleValue ?? 0) * 180 / .pi
            let roll = (face.roll?.doubleValue ?? 0) * 180 / .pi

            DispatchQueue.main.async {
                self.faceDetected = true
                self.yaw = yaw
                self.pitch = pitch
                self.roll = roll

                if self.isRecording {
                    self.recMin = min(self.recMin ?? yaw, yaw)
                    self.recMax = max(self.recMax ?? yaw, yaw)
                    self.recSamples += 1
                }
            }
        }
        request.revision = VNDetectFaceRectanglesRequestRevision3

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspect
        previewLayer.frame = view.bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = previewLayer

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
