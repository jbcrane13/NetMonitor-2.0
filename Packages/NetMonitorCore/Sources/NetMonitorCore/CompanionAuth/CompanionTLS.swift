import Foundation
import Network
import Security

/// TLS for the companion link (#590): TLS 1.3 only, both ends present a `CompanionIdentity`,
/// and each pins the other's public key through `acceptsPeer`. Resumption, tickets, False Start
/// and renegotiation are off, so every connection is a full handshake with certificates.
public enum CompanionTLS {
    /// Exporter label and context for values bound to one session (pairing proofs and the
    /// comparison code).
    static let exporterLabel = "EXPORTER-netmonitor-companion"
    static let exporterContext = Array("netmonitor companion v2".utf8)

    private static let verifyQueue = DispatchQueue(label: "com.netmonitor.companion.tls-verify")

    /// TCP + TLS parameters for either end. `acceptsPeer` gets the peer's pin and is called on
    /// every handshake, so it must read live state. Nil when the identity can't be loaded.
    public static func parameters(
        identity: CompanionIdentity,
        acceptsPeer: @escaping @Sendable (Data) -> Bool
    ) -> NWParameters? {
        guard let secIdentity = try? identity.makeSecIdentity() else { return nil }
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_set_local_identity(options, secIdentity)
        sec_protocol_options_set_peer_authentication_required(options, true)
        sec_protocol_options_set_tls_resumption_enabled(options, false)
        sec_protocol_options_set_tls_tickets_enabled(options, false)
        sec_protocol_options_set_tls_false_start_enabled(options, false)
        sec_protocol_options_set_tls_renegotiation_enabled(options, false)
        sec_protocol_options_set_verify_block(options, { _, trust, complete in
            complete(leafPin(of: trust).map(acceptsPeer) ?? false)
        }, verifyQueue)
        let parameters = NWParameters(tls: tls)
        parameters.includePeerToPeer = true
        return parameters
    }

    /// What a ready connection negotiated, read from its TLS metadata.
    public static func sessionFacts(of connection: NWConnection) -> CompanionSessionFacts {
        guard let metadata = (connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata)?
            .securityProtocolMetadata else {
            return CompanionSessionFacts(tlsVersion: 0, peerPins: [], earlyDataAccepted: false, exporter: nil)
        }
        var pins: [Data] = []
        sec_protocol_metadata_access_peer_certificate_chain(metadata) { certificate in
            let ref = sec_certificate_copy_ref(certificate).takeRetainedValue()
            if let pin = pin(of: ref) {
                pins.append(pin)
            }
        }
        let exporter = exporterLabel.withCString { label in
            exporterContext.withUnsafeBufferPointer { context -> dispatch_data_t? in
                guard let base = context.baseAddress else { return nil }
                return sec_protocol_metadata_create_secret_with_context(
                    metadata, exporterLabel.utf8.count, label, context.count, base, 32
                )
            }
        }
        return CompanionSessionFacts(
            tlsVersion: sec_protocol_metadata_get_negotiated_tls_protocol_version(metadata).rawValue,
            peerPins: pins,
            earlyDataAccepted: sec_protocol_metadata_get_early_data_accepted(metadata),
            exporter: exporter.map { Data($0 as DispatchData) }
        )
    }

    private static func leafPin(of trust: sec_trust_t) -> Data? {
        let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
        guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate], let leaf = chain.first else { return nil }
        return pin(of: leaf)
    }

    private static func pin(of certificate: SecCertificate) -> Data? {
        guard let key = SecCertificateCopyKey(certificate),
              let x963 = SecKeyCopyExternalRepresentation(key, nil) as Data? else { return nil }
        return CompanionIdentity.pin(ofPublicKey: x963)
    }
}

/// The negotiated facts of one connection, as `CompanionTLS.sessionFacts(of:)` reads them.
public struct CompanionSessionFacts: Sendable, Equatable {
    public let tlsVersion: UInt16
    /// Pins of the peer's certificate chain, leaf first; empty when the peer presented none.
    public let peerPins: [Data]
    public let earlyDataAccepted: Bool
    public let exporter: Data?

    public init(tlsVersion: UInt16, peerPins: [Data], earlyDataAccepted: Bool, exporter: Data?) {
        self.tlsVersion = tlsVersion
        self.peerPins = peerPins
        self.earlyDataAccepted = earlyDataAccepted
        self.exporter = exporter
    }

    /// The gate every connection passes at `.ready` before any frame is sent or read. It fails
    /// closed: TLS 1.3, a peer certificate (a resumed session presents none), no early data, and
    /// an exporter, or nil.
    public var verified: CompanionVerifiedSession? {
        guard tlsVersion == tls_protocol_version_t.TLSv13.rawValue,
              !earlyDataAccepted,
              let leaf = peerPins.first,
              let exporter, exporter.count == 32 else { return nil }
        return CompanionVerifiedSession(peerPin: leaf, exporter: exporter)
    }
}

/// A session that passed the gate: who the peer is, and the secret bound to this session.
public struct CompanionVerifiedSession: Sendable, Equatable {
    public let peerPin: Data
    public let exporter: Data

    public init(peerPin: Data, exporter: Data) {
        self.peerPin = peerPin
        self.exporter = exporter
    }
}
