import Foundation

protocol SpeedTestRunning: Sendable {
    func run() async throws -> SpeedTestResult
}

struct SpeedTestRunner: SpeedTestRunning {
    private let executablePath: String
    private let timeoutSeconds: Int
    private let logger: any AppLogging

    init(
        executablePath: String = "/usr/bin/networkQuality",
        timeoutSeconds: Int = 60,
        logger: any AppLogging = NoOpAppLogger()
    ) {
        self.executablePath = executablePath
        self.timeoutSeconds = timeoutSeconds
        self.logger = logger
    }

    func run() async throws -> SpeedTestResult {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            logger.log(.error, category: .speedTest, "networkQuality is unavailable at \(executablePath).")
            throw SpeedTestRunnerError.unavailable
        }

        logger.log(.info, category: .speedTest, "Starting networkQuality run.")
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["-c"]
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            logger.log(.error, category: .speedTest, "Failed to launch networkQuality: \(error.localizedDescription)")
            throw SpeedTestRunnerError.launchFailed(error.localizedDescription)
        }

        do {
            let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))

            while process.isRunning {
                try Task.checkCancellation()

                if Date() >= deadline {
                    process.terminate()
                    logger.log(.error, category: .speedTest, "networkQuality timed out after \(timeoutSeconds) seconds.")
                    throw SpeedTestRunnerError.timedOut
                }

                try await Task.sleep(for: .milliseconds(200))
            }
        } catch is CancellationError {
            if process.isRunning {
                process.terminate()
            }

            logger.log(.info, category: .speedTest, "networkQuality run was cancelled.")
            throw SpeedTestRunnerError.cancelled
        }

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        let errorDetails = String(data: errorOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !output.isEmpty {
            do {
                let result = try SpeedTestResult.decode(from: output)
                logger.log(
                    .info,
                    category: .speedTest,
                    "Completed speed test. download=\(Int(result.downloadMegabitsPerSecond.rounded()))Mbps upload=\(Int(result.uploadMegabitsPerSecond.rounded()))Mbps"
                )
                return result
            } catch let error as SpeedTestRunnerError {
                logger.log(.error, category: .speedTest, error.errorDescription ?? "The speed test failed.")
                throw error
            } catch {
                if process.terminationStatus != 0 {
                    logger.log(
                        .error,
                        category: .speedTest,
                        "networkQuality failed with status \(process.terminationStatus): \(errorDetails)"
                    )
                    throw SpeedTestRunnerError.processFailed(
                        status: Int(process.terminationStatus),
                        details: errorDetails
                    )
                }

                logger.log(.error, category: .speedTest, "networkQuality returned an invalid response.")
                throw SpeedTestRunnerError.invalidResponse
            }
        }

        logger.log(
            .error,
            category: .speedTest,
            "networkQuality returned no output. status=\(process.terminationStatus) details=\(errorDetails)"
        )
        throw SpeedTestRunnerError.processFailed(
            status: Int(process.terminationStatus),
            details: errorDetails
        )
    }
}

enum SpeedTestRunnerError: LocalizedError, Equatable, Sendable {
    case unavailable
    case launchFailed(String)
    case invalidResponse
    case processFailed(status: Int, details: String)
    case networkQualityFailed(domain: String, code: Int)
    case timedOut
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple's networkQuality tool is not available on this Mac."
        case .launchFailed:
            return "The speed test could not be started."
        case .invalidResponse:
            return "The speed test finished, but the result could not be read."
        case let .processFailed(status, details):
            if details.isEmpty {
                return "The speed test failed with exit code \(status)."
            }

            return "The speed test failed with exit code \(status): \(details)"
        case let .networkQualityFailed(domain, code):
            return Self.message(for: domain, code: code)
        case .timedOut:
            return "The speed test took too long and was stopped."
        case .cancelled:
            return "The speed test was cancelled."
        }
    }

    private static func message(for domain: String, code: Int) -> String {
        if domain == "NSURLErrorDomain" {
            switch code {
            case -1009:
                return "No internet connection detected."
            case -1003:
                return "The test server could not be reached. Check your DNS or internet connection."
            case -1001:
                return "The speed test timed out while contacting the test server."
            default:
                break
            }
        }

        return "The speed test failed (\(domain) \(code))."
    }
}
