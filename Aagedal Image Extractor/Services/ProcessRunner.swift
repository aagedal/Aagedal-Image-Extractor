import Foundation

struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

nonisolated func runProcess(
    executableURL: URL,
    arguments: [String],
    currentDirectoryURL: URL? = nil
) async throws -> ProcessResult {
    try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let dir = currentDirectoryURL {
            process.currentDirectoryURL = dir
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { _ in
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let result = ProcessResult(
                exitCode: process.terminationStatus,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
            )
            continuation.resume(returning: result)
        }

        do {
            try process.run()
        } catch {
            continuation.resume(throwing: error)
        }
    }
}
