//
//  ShellCommandRunner.swift
//  NetMonitor
//
//  Reusable actor for executing shell commands with streaming and timeout support.
//

import Foundation

/// Error types for shell command execution
enum ToolError: Error, LocalizedError {
    case commandNotFound(String)
    case timeout(TimeInterval)
    case cancelled
    case executionFailed(exitCode: Int32, stderr: String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .commandNotFound(let path):
            return "Command not found: \(path)"
        case .timeout(let duration):
            return "Command timed out after \(Int(duration)) seconds"
        case .cancelled:
            return "Command was cancelled"
        case .executionFailed(let exitCode, let stderr):
            if stderr.isEmpty {
                return "Command failed with exit code \(exitCode)"
            }
            return "Command failed (exit \(exitCode)): \(stderr)"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}

/// Result of a completed shell command
struct CommandOutput: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let duration: TimeInterval
}

/// Actor for executing shell commands safely
actor ShellCommandRunner {
    private var currentProcess: Process?
    private var isCancelled = false

    /// Run a command and return the full output
    /// - Parameters:
    ///   - executable: Path to the executable (e.g., "/sbin/ping")
    ///   - arguments: Command arguments
    ///   - timeout: Maximum execution time in seconds (default 30)
    /// - Returns: CommandOutput with stdout, stderr, exit code, and duration
    func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = 30
    ) async throws -> CommandOutput {
        // Verify executable exists
        guard FileManager.default.fileExists(atPath: executable) else {
            throw ToolError.commandNotFound(executable)
        }

        isCancelled = false
        let startTime = Date()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        currentProcess = process

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let tracker = ContinuationTracker()

                // Set up timeout
                let timeoutTask = Task {
                    try await Task.sleep(for: .seconds(timeout))
                    if tracker.tryResume() {
                        process.terminate()
                        continuation.resume(throwing: ToolError.timeout(timeout))
                    }
                }

                // Run process
                do {
                    try process.run()
                } catch {
                    timeoutTask.cancel()
                    if tracker.tryResume() {
                        continuation.resume(throwing: ToolError.executionFailed(exitCode: -1, stderr: error.localizedDescription))
                    }
                    return
                }

                // Wait for completion in background
                Task.detached { [weak self] in
                    process.waitUntilExit()
                    timeoutTask.cancel()

                    let duration = Date().timeIntervalSince(startTime)
                    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                    await self?.clearCurrentProcess()

                    if tracker.tryResume() {
                        if self != nil {
                            let wasCancelled = await self?.isCancelled ?? false
                            if wasCancelled {
                                continuation.resume(throwing: ToolError.cancelled)
                                return
                            }
                        }

                        let output = CommandOutput(
                            stdout: stdout,
                            stderr: stderr,
                            exitCode: process.terminationStatus,
                            duration: duration
                        )
                        continuation.resume(returning: output)
                    }
                }
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    /// Stream command output line-by-line
    /// - Parameters:
    ///   - executable: Path to the executable
    ///   - arguments: Command arguments
    /// - Returns: AsyncThrowingStream of output lines
    func stream(
        _ executable: String,
        arguments: [String]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // Verify executable exists
                guard FileManager.default.fileExists(atPath: executable) else {
                    continuation.finish(throwing: ToolError.commandNotFound(executable))
                    return
                }

                self.resetCancelled()

                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                self.setCurrentProcess(process)

                // Set up line-by-line reading
                let fileHandle = stdoutPipe.fileHandleForReading

                // Read stdout asynchronously
                fileHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        return
                    }

                    if let string = String(data: data, encoding: .utf8) {
                        // Split into lines and yield each
                        let lines = string.components(separatedBy: .newlines)
                        for line in lines where !line.isEmpty {
                            continuation.yield(line)
                        }
                    }
                }

                // Handle process termination
                process.terminationHandler = { [weak self] proc in
                    fileHandle.readabilityHandler = nil

                    Task {
                        await self?.clearCurrentProcess()
                        let wasCancelled = await self?.isCancelled ?? false

                        if wasCancelled {
                            continuation.finish(throwing: ToolError.cancelled)
                        } else if proc.terminationStatus != 0 {
                            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                            continuation.finish(throwing: ToolError.executionFailed(exitCode: proc.terminationStatus, stderr: stderr))
                        } else {
                            continuation.finish()
                        }
                    }
                }

                do {
                    try process.run()
                } catch {
                    self.clearCurrentProcess()
                    continuation.finish(throwing: ToolError.executionFailed(exitCode: -1, stderr: error.localizedDescription))
                }
            }
        }
    }

    /// Cancel the currently running command
    func cancel() {
        isCancelled = true
        currentProcess?.terminate()
        currentProcess = nil
    }

    private func setCurrentProcess(_ process: Process) {
        currentProcess = process
    }

    private func clearCurrentProcess() {
        currentProcess = nil
    }

    private func resetCancelled() {
        isCancelled = false
    }
}
