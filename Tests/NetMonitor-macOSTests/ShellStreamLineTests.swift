import Foundation
import Testing
@testable import NetMonitor_macOS

/// #474: streamed shell output keeps every line, including ones written just before exit.
struct ShellStreamLineTests {
    @Test("A fast command's output is never lost", .timeLimit(.minutes(1)))
    func fastCommandKeepsEveryLine() async throws {
        for _ in 0..<25 {
            let runner = ShellCommandRunner()
            var lines: [String] = []
            for try await line in await runner.stream("/bin/sh", arguments: ["-c", "echo line1; echo line2; printf line3"]) {
                lines.append(line)
            }
            #expect(lines == ["line1", "line2", "line3"])
        }
    }

    @Test("Output larger than one read keeps every line in order")
    func largeOutput() async throws {
        let runner = ShellCommandRunner()
        var lines: [String] = []
        for try await line in await runner.stream("/usr/bin/seq", arguments: ["1", "20000"]) {
            lines.append(line)
        }
        #expect(lines.count == 20000)
        #expect(lines.first == "1")
        #expect(lines.last == "20000")
        #expect(lines == (1...20000).map(String.init))
    }
}
