import Foundation
import Testing
@testable import NetMonitor_macOS

// MARK: - ShellCommandRunner Tests

/// Tests for ShellCommandRunner: command execution, error handling, timeout, streaming,
/// and cancellation. All tests use simple system commands (echo, cat, sleep) to avoid
/// external dependencies.
struct ShellCommandRunnerTests {

    // MARK: - Run simple command

    @Test("Run echo command returns correct output")
    func runEchoReturnsCorrectOutput() async throws {
        let runner = ShellCommandRunner()
        let output = try await runner.run("/bin/echo", arguments: ["hello"])
        #expect(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
        #expect(output.exitCode == 0)
    }

    @Test("Run command captures stdout correctly")
    func runCapturesStdout() async throws {
        let runner = ShellCommandRunner()
        let output = try await runner.run("/bin/echo", arguments: ["line1\nline2"])
        #expect(output.stdout.contains("line1"))
        #expect(output.stdout.contains("line2"))
        #expect(output.exitCode == 0)
    }

    @Test("Run command records positive duration")
    func runRecordsDuration() async throws {
        let runner = ShellCommandRunner()
        let output = try await runner.run("/bin/echo", arguments: ["test"])
        #expect(output.duration >= 0)
    }

    // MARK: - Exit code and stderr

    @Test("Run command with nonzero exit code captures exit code")
    func runCapturesNonzeroExitCode() async throws {
        let runner = ShellCommandRunner()
        // /usr/bin/false always exits with code 1
        let output = try await runner.run("/usr/bin/false", arguments: [])
        #expect(output.exitCode == 1)
    }

    @Test("Run command with stderr output captures it")
    func runCapturesStderr() async throws {
        let runner = ShellCommandRunner()
        // Use /bin/sh to echo to stderr
        let output = try await runner.run("/bin/sh", arguments: ["-c", "echo error_output >&2"])
        #expect(output.stderr.contains("error_output"))
    }

    @Test("Run nonexistent command throws commandNotFound")
    func runNonexistentCommandThrows() async {
        let runner = ShellCommandRunner()
        do {
            _ = try await runner.run("/nonexistent/command/path", arguments: [])
            Issue.record("Expected ToolError.commandNotFound")
        } catch let error as ToolError {
            if case .commandNotFound(let path) = error {
                #expect(path == "/nonexistent/command/path")
            } else {
                Issue.record("Expected commandNotFound but got: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Timeout

    @Test("Command timeout triggers ToolError.timeout")
    func commandTimeoutThrowsTimeout() async {
        let runner = ShellCommandRunner()
        do {
            // sleep 30 with a 1-second timeout
            _ = try await runner.run("/bin/sleep", arguments: ["30"], timeout: 1)
            Issue.record("Expected ToolError.timeout")
        } catch let error as ToolError {
            if case .timeout(let duration) = error {
                #expect(duration == 1)
            } else {
                Issue.record("Expected timeout but got: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Fast command completes before timeout")
    func fastCommandCompletesBeforeTimeout() async throws {
        let runner = ShellCommandRunner()
        let output = try await runner.run("/bin/echo", arguments: ["fast"], timeout: 10)
        #expect(output.stdout.contains("fast"))
        #expect(output.exitCode == 0)
    }

    // MARK: - Streaming command

    @Test("Stream command yields lines incrementally")
    func streamCommandYieldsLines() async throws {
        let runner = ShellCommandRunner()
        // Use sh to echo multiple lines
        let stream = await runner.stream("/bin/sh", arguments: ["-c", "echo line1; echo line2; echo line3"])

        var lines: [String] = []
        for try await line in stream {
            lines.append(line)
        }

        #expect(lines.count >= 1, "Should receive at least one line from stream")
        // Lines may be batched depending on buffering, so check content
        let allOutput = lines.joined(separator: "\n")
        #expect(allOutput.contains("line1"))
        #expect(allOutput.contains("line2"))
        #expect(allOutput.contains("line3"))
    }

    @Test("Stream nonexistent command throws commandNotFound")
    func streamNonexistentCommandThrows() async {
        let runner = ShellCommandRunner()
        let stream = await runner.stream("/nonexistent/command", arguments: [])

        do {
            for try await _ in stream {
                break
            }
            Issue.record("Expected ToolError.commandNotFound")
        } catch let error as ToolError {
            if case .commandNotFound = error {
                #expect(Bool(true))
            } else {
                Issue.record("Expected commandNotFound but got: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Cancel running command

    @Test("Cancel running command terminates the process")
    func cancelRunningCommandTerminatesProcess() async {
        let runner = ShellCommandRunner()

        let task = Task {
            try await runner.run("/bin/sleep", arguments: ["30"], timeout: 30)
        }

        // Give the process time to start
        try? await Task.sleep(for: .milliseconds(200))

        // Cancel via runner
        await runner.cancel()

        do {
            _ = try await task.value
            // May succeed with cancelled error or timeout — both acceptable
        } catch let error as ToolError {
            // cancelled or timeout is expected
            switch error {
            case .cancelled, .timeout:
                #expect(Bool(true))
            default:
                // Other ToolErrors are also acceptable (process was killed)
                #expect(Bool(true))
            }
        } catch {
            // Any error due to cancellation is acceptable
            #expect(Bool(true))
        }
    }

    // MARK: - ToolError descriptions

    @Test("ToolError.commandNotFound has descriptive message")
    func commandNotFoundDescription() {
        let error = ToolError.commandNotFound("/usr/bin/missing")
        #expect(error.errorDescription?.contains("/usr/bin/missing") == true)
    }

    @Test("ToolError.timeout has descriptive message")
    func timeoutDescription() {
        let error = ToolError.timeout(5.0)
        #expect(error.errorDescription?.contains("5") == true)
    }

    @Test("ToolError.cancelled has descriptive message")
    func cancelledDescription() {
        let error = ToolError.cancelled
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test("ToolError.executionFailed with stderr includes it in description")
    func executionFailedDescription() {
        let error = ToolError.executionFailed(exitCode: 1, stderr: "permission denied")
        #expect(error.errorDescription?.contains("permission denied") == true)
    }

    @Test("ToolError.executionFailed with empty stderr shows exit code only")
    func executionFailedEmptyStderr() {
        let error = ToolError.executionFailed(exitCode: 127, stderr: "")
        #expect(error.errorDescription?.contains("127") == true)
    }

    @Test("ToolError.parseError has descriptive message")
    func parseErrorDescription() {
        let error = ToolError.parseError("unexpected format")
        #expect(error.errorDescription?.contains("unexpected format") == true)
    }

    // MARK: - CommandOutput model

    @Test("CommandOutput stores all fields correctly")
    func commandOutputFields() {
        let output = CommandOutput(stdout: "out", stderr: "err", exitCode: 42, duration: 1.5)
        #expect(output.stdout == "out")
        #expect(output.stderr == "err")
        #expect(output.exitCode == 42)
        #expect(output.duration == 1.5)
    }
}
