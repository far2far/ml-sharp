import Foundation
import SwiftUI

/// Overall pipeline status.
enum PipelineStatus: Equatable {
    case idle
    case running(InferenceStage)
    case parsingPLY
    case done
    case failed(String)
    case cancelled

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .running(let stage): return stage.rawValue
        case .parsingPLY: return "Parsing point cloud"
        case .done: return "Done"
        case .failed(let msg): return "Error: \(msg)"
        case .cancelled: return "Cancelled"
        }
    }

    var isRunning: Bool {
        switch self {
        case .running, .parsingPLY: return true
        default: return false
        }
    }
}

/// Central application state. Orchestrates:
///   image selection → SharpRunner → PLYParser → GaussianCloud
@Observable
final class AppState {
    // MARK: - Published state

    /// The user-selected input image URL.
    var inputImageURL: URL?

    /// Loaded NSImage for preview (set once inputImageURL is valid).
    var inputImage: NSImage?

    /// Parsed point cloud, ready for rendering.
    var cloud: GaussianCloud?

    /// Current pipeline status.
    var status: PipelineStatus = .idle

    // MARK: - Private

    private let runner = SharpRunner()
    private var runTask: Task<Void, Never>?

    // MARK: - Actions

    /// Set a new input image and automatically start prediction.
    func setImage(url: URL) {
        // Reset previous state.
        cancel()
        cloud = nil
        inputImageURL = url
        inputImage = NSImage(contentsOf: url)
        startPrediction()
    }

    /// Cancel current inference, if any.
    func cancel() {
        runTask?.cancel()
        runner.cancel()
        runTask = nil
        if status.isRunning {
            status = .cancelled
        }
    }

    // MARK: - Pipeline

    private func startPrediction() {
        guard let imageURL = inputImageURL else { return }

        status = .running(.preprocessing)

        runTask = Task { [weak self] in
            guard let self else { return }

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("SharpViewer_\(UUID().uuidString)")
                .path

            do {
                try FileManager.default.createDirectory(
                    atPath: tempDir,
                    withIntermediateDirectories: true
                )

                let plyURL = try await runner.run(
                    imagePath: imageURL.path,
                    outputDir: tempDir,
                    onStage: { [weak self] stage in
                        Task { @MainActor in
                            self?.status = .running(stage)
                        }
                    }
                )

                if Task.isCancelled { return }

                await MainActor.run { self.status = .parsingPLY }

                let parsed = try PLYParser.parse(url: plyURL)

                if Task.isCancelled { return }

                await MainActor.run {
                    self.cloud = parsed
                    self.status = .done
                }
            } catch is CancellationError {
                await MainActor.run { self.status = .cancelled }
            } catch {
                await MainActor.run {
                    self.status = .failed(error.localizedDescription)
                }
            }
        }
    }
}
