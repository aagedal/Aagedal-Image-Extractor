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
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // File-backed streams cannot fill a pipe and block the child before it exits.
                let fm = FileManager.default
                let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: directory) }
                let stdoutURL = directory.appendingPathComponent("stdout")
                let stderrURL = directory.appendingPathComponent("stderr")
                try Data().write(to: stdoutURL)
                try Data().write(to: stderrURL)
                let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
                defer { try? stdoutHandle.close() }
                let stderrHandle = try FileHandle(forWritingTo: stderrURL)
                defer { try? stderrHandle.close() }

                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                process.currentDirectoryURL = currentDirectoryURL
                process.standardOutput = stdoutHandle
                process.standardError = stderrHandle
                try process.run()
                process.waitUntilExit()

                continuation.resume(returning: ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self),
                    stderr: String(decoding: try Data(contentsOf: stderrURL), as: UTF8.self)
                ))
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
