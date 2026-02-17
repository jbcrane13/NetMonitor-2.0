import Foundation

/// Unified error type for all network service operations.
public enum NetworkError: LocalizedError, Sendable {
    case timeout
    case connectionFailed
    case noNetwork
    case invalidHost
    case permissionDenied
    case dnsLookupFailed
    case serverError
    case invalidResponse
    case cancelled
    case unknown(any Error & Sendable)

    public var errorDescription: String? {
        switch self {
        case .timeout: "Connection timed out"
        case .connectionFailed: "Could not connect to host"
        case .noNetwork: "No network connection available"
        case .invalidHost: "Invalid hostname or IP address"
        case .permissionDenied: "Permission denied"
        case .dnsLookupFailed: "DNS lookup failed"
        case .serverError: "Server returned an error"
        case .invalidResponse: "Invalid response from server"
        case .cancelled: "Operation was cancelled"
        case .unknown(let error): error.localizedDescription
        }
    }

    public var userFacingMessage: String {
        switch self {
        case .timeout: "The connection timed out. Please check the host and try again."
        case .connectionFailed: "Unable to establish a connection. Please verify the host is reachable."
        case .noNetwork: "No network connection. Please check your internet connection."
        case .invalidHost: "The hostname or IP address is invalid. Please check and try again."
        case .permissionDenied: "Network permission was denied. Please check your settings."
        case .dnsLookupFailed: "DNS lookup failed. Please check the domain name and try again."
        case .serverError: "The server returned an error. Please try again later."
        case .invalidResponse: "Received an invalid response. Please try again."
        case .cancelled: "The operation was cancelled."
        case .unknown: "An unexpected error occurred. Please try again."
        }
    }

    /// Convert from any error type, preserving NetworkError identity.
    public static func from(_ error: any Error) -> NetworkError {
        if let networkError = error as? NetworkError {
            return networkError
        }
        if error is CancellationError {
            return .cancelled
        }
        // Wrap non-Sendable errors as unknown with a string description
        struct StringError: Error, Sendable {
            let description: String
            var localizedDescription: String { description }
        }
        return .unknown(StringError(description: error.localizedDescription))
    }
}
