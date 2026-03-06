import Foundation

/// Inference stages parsed from SHARP's stdout log lines.
enum InferenceStage: String, Sendable {
    case loadingModel     = "Loading model"
    case preprocessing    = "Preprocessing"
    case runningInference = "Running inference"
    case postprocessing   = "Postprocessing"
    case saving           = "Saving result"
}

/// Wraps the `sharp predict` CLI as a subprocess.
///
/// Usage:
/// ```
/// let runner = SharpRunner()
/// let plyURL = try await runner.run(imagePath: ..., outputDir: ...) { stage in
///     // update UI
/// }
/// ```
final class SharpRunner: Sendable {

    /// Path to the `sharp` executable inside the project venv.
    private let executable = "/Users/falarcon/sharp/.venv/bin/sharp"

    /// PEM bundle for HTTPS requests made by SHARP.
    private let certBundle = "/Users/falarcon/sharp/combined-certs.pem"

    /// Currently running process (for cancellation).
    private nonisolated(unsafe) var _process: Process?
    private let processLock = NSLock()

    private var process: Process? {
        get { processLock.withLock { _process } }
        set { processLock.withLock { _process = newValue } }
    }

    // MARK: - Public

    /// Run `sharp predict` and return the URL of the generated PLY file.
    ///
    /// - Parameters:
    ///   - imagePath: Absolute path to the input image.
    ///   - outputDir: Directory where the PLY will be written.
    ///   - onStage: Called on arbitrary thread when a new inference stage is detected.
    /// - Returns: URL of the output PLY file.
    func run(
        imagePath: String,
        outputDir: String,
        onStage: @escaping @Sendable (InferenceStage) -> Void
    ) async throws -> URL {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = ["predict", "-i", imagePath, "-o", outputDir]

        var env = ProcessInfo.processInfo.environment
        env["SSL_CERT_FILE"] = certBundle
        env["REQUESTS_CA_BUNDLE"] = certBundle
        env["PYTHONUNBUFFERED"] = "1"
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe  // merge stderr so we see everything

        process = proc

        // Read stdout line-by-line and map to stages.
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8) else { return }
            for line in text.components(separatedBy: "\n") {
                if let stage = Self.parseStage(from: line) {
                    onStage(stage)
                }
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            proc.terminationHandler = { [weak self] process in
                handle.readabilityHandler = nil
                self?.process = nil

                if process.terminationStatus == 0 {
                    // Derive output PLY path: {outputDir}/{imageStem}.ply
                    let stem = (imagePath as NSString).lastPathComponent
                        .components(separatedBy: ".").dropLast().joined(separator: ".")
                    let plyURL = URL(fileURLWithPath: outputDir)
                        .appendingPathComponent(stem)
                        .appendingPathExtension("ply")
                    continuation.resume(returning: plyURL)
                } else if process.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: CancellationError())
                } else {
                    let error = NSError(
                        domain: "SharpRunner",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey:
                            "sharp predict exited with code \(process.terminationStatus)"]
                    )
                    continuation.resume(throwing: error)
                }
            }

            do {
                try proc.run()
            } catch {
                handle.readabilityHandler = nil
                self.process = nil
                continuation.resume(throwing: error)
            }
        }
    }

    /// Cancel the running subprocess (sends SIGTERM).
    func cancel() {
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
    }

    // MARK: - Log parsing

    /// Parse a SHARP log line and return the matching inference stage, if any.
    ///
    /// Log format: `YYYY-MM-DD HH:MM:SS | LEVEL | message`
    private static func parseStage(from line: String) -> InferenceStage? {
        let lower = line.lowercased()
        if lower.contains("downloading default model") || lower.contains("loading") && lower.contains("model") {
            return .loadingModel
        } else if lower.contains("running preprocessing") || lower.contains("preprocessing") {
            return .preprocessing
        } else if lower.contains("running inference") {
            return .runningInference
        } else if lower.contains("running postprocessing") || lower.contains("postprocessing") {
            return .postprocessing
        } else if lower.contains("saving 3dgs") || lower.contains("saving") {
            return .saving
        }
        return nil
    }
}
