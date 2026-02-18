import Foundation
import Testing
@testable import NetMonitorCore

@Suite("NetworkError.errorDescription")
struct NetworkErrorDescriptionTests {
    @Test func timeout() {
        #expect(NetworkError.timeout.errorDescription == "Connection timed out")
    }

    @Test func connectionFailed() {
        #expect(NetworkError.connectionFailed.errorDescription == "Could not connect to host")
    }

    @Test func noNetwork() {
        #expect(NetworkError.noNetwork.errorDescription == "No network connection available")
    }

    @Test func invalidHost() {
        #expect(NetworkError.invalidHost.errorDescription == "Invalid hostname or IP address")
    }

    @Test func permissionDenied() {
        #expect(NetworkError.permissionDenied.errorDescription == "Permission denied")
    }

    @Test func dnsLookupFailed() {
        #expect(NetworkError.dnsLookupFailed.errorDescription == "DNS lookup failed")
    }

    @Test func serverError() {
        #expect(NetworkError.serverError.errorDescription == "Server returned an error")
    }

    @Test func invalidResponse() {
        #expect(NetworkError.invalidResponse.errorDescription == "Invalid response from server")
    }

    @Test func cancelled() {
        #expect(NetworkError.cancelled.errorDescription == "Operation was cancelled")
    }

    @Test func unknownUsesWrappedErrorDescription() {
        struct FakeError: LocalizedError, Sendable {
            var errorDescription: String? { "fake underlying error" }
        }
        let error = NetworkError.unknown(FakeError())
        #expect(error.errorDescription == "fake underlying error")
    }
}

@Suite("NetworkError.userFacingMessage")
struct NetworkErrorUserFacingMessageTests {
    @Test func timeout() {
        #expect(NetworkError.timeout.userFacingMessage == "The connection timed out. Please check the host and try again.")
    }

    @Test func connectionFailed() {
        #expect(NetworkError.connectionFailed.userFacingMessage == "Unable to establish a connection. Please verify the host is reachable.")
    }

    @Test func noNetwork() {
        #expect(NetworkError.noNetwork.userFacingMessage == "No network connection. Please check your internet connection.")
    }

    @Test func invalidHost() {
        #expect(NetworkError.invalidHost.userFacingMessage == "The hostname or IP address is invalid. Please check and try again.")
    }

    @Test func permissionDenied() {
        #expect(NetworkError.permissionDenied.userFacingMessage == "Network permission was denied. Please check your settings.")
    }

    @Test func dnsLookupFailed() {
        #expect(NetworkError.dnsLookupFailed.userFacingMessage == "DNS lookup failed. Please check the domain name and try again.")
    }

    @Test func serverError() {
        #expect(NetworkError.serverError.userFacingMessage == "The server returned an error. Please try again later.")
    }

    @Test func invalidResponse() {
        #expect(NetworkError.invalidResponse.userFacingMessage == "Received an invalid response. Please try again.")
    }

    @Test func cancelled() {
        #expect(NetworkError.cancelled.userFacingMessage == "The operation was cancelled.")
    }

    @Test func unknownHasGenericMessage() {
        struct FakeError: Error, Sendable {
            var localizedDescription: String { "internal details" }
        }
        let error = NetworkError.unknown(FakeError())
        #expect(error.userFacingMessage == "An unexpected error occurred. Please try again.")
    }
}

@Suite("NetworkError.from")
struct NetworkErrorFromTests {
    @Test func preservesNetworkErrorIdentity() {
        let cases: [NetworkError] = [
            .timeout, .connectionFailed, .noNetwork, .invalidHost,
            .permissionDenied, .dnsLookupFailed, .serverError,
            .invalidResponse, .cancelled
        ]
        for original in cases {
            let result = NetworkError.from(original)
            // errorDescription is unique per case, so matching it confirms identity
            #expect(result.errorDescription == original.errorDescription)
        }
    }

    @Test func cancellationErrorMapsToCancelled() {
        let result = NetworkError.from(CancellationError())
        #expect(result.errorDescription == NetworkError.cancelled.errorDescription)
    }

    @Test func genericErrorWrappedAsUnknown() {
        // NetworkError.from() wraps unknown errors in a StringError which doesn't conform
        // to LocalizedError, so we verify the .unknown case via its constant userFacingMessage
        struct GenericError: Error {}
        let result = NetworkError.from(GenericError())
        #expect(result.userFacingMessage == "An unexpected error occurred. Please try again.")
    }

    @Test func unknownNetworkErrorPreservesIdentity() {
        struct FakeError: Error, Sendable {
            var localizedDescription: String { "fake" }
        }
        let original = NetworkError.unknown(FakeError())
        let result = NetworkError.from(original)
        // A NetworkError passed to from() returns itself unchanged
        #expect(result.errorDescription == original.errorDescription)
    }
}
