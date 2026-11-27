import Foundation
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The Ask model the apps use (#452): the on-device model with tool calling on iOS 27 / macOS 27
/// and later, and one that is never available everywhere else.
public enum AskModel {
    public static let shared: any AskModelProtocol = make()

    static func make() -> any AskModelProtocol {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            return SystemAskModel()
        }
        #endif
        return UnavailableAskModel()
    }
}

/// No model: where the on-device model can't run, and in UI tests of the hidden Ask card.
public struct UnavailableAskModel: AskModelProtocol {
    public init() {}

    public var isAvailable: Bool { false }

    public func answer(_ question: String, instructions: String, toolbox: AskToolbox) async -> String? {
        nil
    }
}

#if canImport(FoundationModels)
/// Answers with the system language model calling `AskToolbox`'s tools. Everything stays on the
/// device; questions and tool results carry device names and addresses, so nothing is logged.
///
/// From the #447 spike: the toolbox caps calls itself and answers "limit reached" (approach C),
/// and `onToolCall` stops the turn past `AskToolbox.hardStop` (approach D). Tool calling is left
/// at its default: `.required` never stops. The caller cancels by cancelling its task.
@available(iOS 27.0, macOS 27.0, *)
struct SystemAskModel: AskModelProtocol {
    private static let logger = Logger(subsystem: "com.netmonitor", category: "AskModel")

    var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    func answer(_ question: String, instructions: String, toolbox: AskToolbox) async -> String? {
        var tools: [any Tool] = [
            FindDevicesTool(toolbox: toolbox), DeviceStatusTool(toolbox: toolbox), DeviceLatencyHistoryTool(toolbox: toolbox),
            EventsTool(toolbox: toolbox), FlakyDevicesTool(toolbox: toolbox)
        ]
        // Only where the app can measure (#579).
        if toolbox.hasLiveTools {
            tools += [PingDeviceTool(toolbox: toolbox), NetworkStatusTool(toolbox: toolbox)] as [any Tool]
        }
        let profile = LanguageModelSession.Profile {
            Instructions(instructions)
            tools
        }
        // Greedy: the same question on the same data gets the same answer.
        .samplingMode(.greedy)
        .onToolCall { _ in try toolbox.admit() }
        do {
            let session = LanguageModelSession(profile: profile)
            // Interactive: while it runs, companion requests are answered busy (#586).
            return try await ModelAdmission.shared.runLocal(.interactive) {
                try await session.respond(to: question, options: GenerationOptions(maximumResponseTokens: 220)).content
            }
        } catch {
            // The error's type only: its description can quote the question or tool results.
            Self.logger.error("Ask model failed: \(String(describing: type(of: error)), privacy: .public)")
            return nil
        }
    }
}

@available(iOS 27.0, macOS 27.0, *)
@Generable
struct AskPhraseArguments {
    // No example device here: given "such as the printer", the model searched for the printer
    // when asked which devices were offline.
    @Guide(description: "The user's own words for one device, or all for every device with its status")
    var phrase: String
}

@available(iOS 27.0, macOS 27.0, *)
@Generable
struct AskDeviceArguments {
    @Guide(description: "The device's id from findDevices, such as dev-a")
    var id: String
}

@available(iOS 27.0, macOS 27.0, *)
@Generable
struct AskEventsArguments {
    @Guide(description: "The time range the user asked about; last7Days when they named none", .anyOf(AskRange.allCases.map(\.rawValue)))
    var range: String
    @Guide(description: "The kind of event: deviceWentOffline when a device dropped off or left, deviceJoined when one is new, or any",
           .anyOf(["any"] + AskEventKind.allCases.map(\.rawValue)))
    var type: String
}

@available(iOS 27.0, macOS 27.0, *)
@Generable
struct AskRangeArguments {
    @Guide(description: "The time range the user asked about; last7Days when they named none", .anyOf(AskRange.allCases.map(\.rawValue)))
    var range: String
}

@available(iOS 27.0, macOS 27.0, *)
struct FindDevicesTool: Tool {
    let toolbox: AskToolbox
    let name = "findDevices"
    let description = "Find saved devices by the user's words for one (a name, a kind or a maker), or list every device with all. "
        + "Returns each device's id, name, kind, status, last seen time and address."

    func call(arguments: AskPhraseArguments) async throws -> String {
        toolbox.findDevices(arguments.phrase)
    }
}

@available(iOS 27.0, macOS 27.0, *)
struct DeviceStatusTool: Tool {
    let toolbox: AskToolbox
    let name = "deviceStatus"
    let description = "Whether one device is online or offline, when it was last seen and its last reply time."

    func call(arguments: AskDeviceArguments) async throws -> String {
        toolbox.deviceStatus(arguments.id)
    }
}

@available(iOS 27.0, macOS 27.0, *)
struct DeviceLatencyHistoryTool: Tool {
    let toolbox: AskToolbox
    let name = "deviceLatencyHistory"
    let description = "One device's recent latency: average, highest, spikes, and how often it went offline."

    func call(arguments: AskDeviceArguments) async throws -> String {
        toolbox.deviceLatencyHistory(arguments.id)
    }
}

@available(iOS 27.0, macOS 27.0, *)
struct EventsTool: Tool {
    let toolbox: AskToolbox
    let name = "events"
    let description = "Network events in a time range, newest first: devices joining or leaving, connectivity, speed, "
        + "gateway and VPN changes, scans."

    func call(arguments: AskEventsArguments) async throws -> String {
        toolbox.events(arguments.range, type: arguments.type)
    }
}

@available(iOS 27.0, macOS 27.0, *)
@Generable
struct AskNoArguments {}

@available(iOS 27.0, macOS 27.0, *)
struct PingDeviceTool: Tool {
    let toolbox: AskToolbox
    let name = "pingDevice"
    let description = "Ping one device now, 3 times: how many replies came back and the average reply time. "
        + "For whether a device answers right now."

    func call(arguments: AskDeviceArguments) async throws -> String {
        await toolbox.pingDevice(arguments.id)
    }
}

@available(iOS 27.0, macOS 27.0, *)
struct NetworkStatusTool: Tool {
    let toolbox: AskToolbox
    let name = "networkStatus"
    let description = "Check the connection now: its type, and pings to the gateway and to a public internet address (8.8.8.8)."

    func call(arguments: AskNoArguments) async throws -> String {
        await toolbox.networkStatus()
    }
}

@available(iOS 27.0, macOS 27.0, *)
struct FlakyDevicesTool: Tool {
    let toolbox: AskToolbox
    let name = "flakyDevices"
    let description = "The devices that were flaky in a time range, ranked by the app: those that went offline repeatedly "
        + "or had latency spikes."

    func call(arguments: AskRangeArguments) async throws -> String {
        toolbox.flakyDevices(arguments.range)
    }
}
#endif
