import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

// MARK: - TargetProtocol Icon Names (EnumExtensions.swift)

struct EnumExtensionsTests {

    @Test func httpIconName() {
        #expect(TargetProtocol.http.iconName == "network")
    }

    @Test func httpsIconName() {
        #expect(TargetProtocol.https.iconName == "network")
    }

    @Test func icmpIconName() {
        #expect(TargetProtocol.icmp.iconName == "waveform.path.ecg")
    }

    @Test func tcpIconName() {
        #expect(TargetProtocol.tcp.iconName == "arrow.left.arrow.right")
    }
}

// MARK: - ToolError Descriptions (ShellCommandRunner.swift)

struct ToolErrorTests {

    @Test func commandNotFoundDescription() {
        let error = ToolError.commandNotFound("/usr/bin/fake")
        #expect(error.errorDescription == "Command not found: /usr/bin/fake")
    }

    @Test func timeoutDescription() {
        let error = ToolError.timeout(30)
        #expect(error.errorDescription == "Command timed out after 30 seconds")
    }

    @Test func cancelledDescription() {
        #expect(ToolError.cancelled.errorDescription == "Command was cancelled")
    }

    @Test func executionFailedWithStderr() {
        let error = ToolError.executionFailed(exitCode: 1, stderr: "permission denied")
        #expect(error.errorDescription == "Command failed (exit 1): permission denied")
    }

    @Test func executionFailedEmptyStderr() {
        let error = ToolError.executionFailed(exitCode: 2, stderr: "")
        #expect(error.errorDescription == "Command failed with exit code 2")
    }

    @Test func parseErrorDescription() {
        let error = ToolError.parseError("invalid format")
        #expect(error.errorDescription == "Parse error: invalid format")
    }
}
