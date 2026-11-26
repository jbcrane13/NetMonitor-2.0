# NetMonitor Companion Protocol API

This document describes the communication protocol between the NetMonitor macOS application and companion apps (iOS/iPadOS).

## Service Discovery

NetMonitor advertises itself via Bonjour (mDNS) for automatic discovery on the local network.

| Property | Value |
|----------|-------|
| Service Type | `_netmon._tcp` |
| Port | `8849` |
| Service Name | `NetMonitor` |
| TXT `pv` | Protocol version, `2` (#590). Missing on a Mac before v2 |
| TXT `mac` | The Mac's ID (a UUID), matching the paired Mac on the phone |

The TXT record is a hint for the phone's screen ("Paired", "Not paired", "Needs an update"). Nothing about the link's security depends on it.

### Discovery Example (Swift)

```swift
import Network

let browser = NWBrowser(for: .bonjour(type: "_netmon._tcp", domain: nil), using: .tcp)
browser.browseResultsChangedHandler = { results, changes in
    for result in results {
        // result.endpoint contains the discovered NetMonitor service
    }
}
browser.start(queue: .main)
```

## Connection

Every connection is TLS 1.3 with both ends presenting a pinned identity; there is no plain TCP mode (#590). Build the parameters with `CompanionTLS.parameters(identity:acceptsPeer:)` from NetMonitorCore. See [Authentication and encryption](#authentication-and-encryption).

### Connection Example (Swift)

```swift
let identity = try CompanionIdentity(rawRepresentation: pairedMac.phoneIdentity)
let parameters = CompanionTLS.parameters(identity: identity, acceptsPeer: { $0 == pairedMac.macPin })!
let connection = NWConnection(to: endpoint, using: parameters)
connection.stateUpdateHandler = { state in
    switch state {
    case .ready:
        // Check CompanionTLS.sessionFacts(of: connection).verified, then wait for the Mac's
        // serverHello before sending anything.
    case .failed(let error):
        // A TLS error here means the Mac refused this phone's key, or it isn't the paired Mac.
    default:
        break
    }
}
connection.start(queue: .main)
```

## Authentication and encryption

Added in protocol v2 (#590). The link carries device lists, scan results, commands such as Wake on LAN, and model prompts. Only a paired iPhone may connect, and everything is encrypted.

### Transport

- **TLS 1.3 only**, through Network.framework. Each end has a P-256 identity (`CompanionIdentity`) and a minimal self-signed certificate made from it.
- **Pinning.** The phone's verify block accepts the Mac only if the SHA-256 of its X9.63 public key (its **pin**) is the paired Mac's, or the one in the QR. The Mac lets any certificate complete TLS, then decides at `.ready` from the verified peer pin.
  - A key it trusts → a paired link.
  - An unknown key while a window can admit it → a pairing link.
  - Anything else → **`serverHello{mode: refused}`**, then close; nothing is read.
  - The refusal travels over the verified session, so the phone treats it as definite: "Forget This Mac, then pair again", with no retry. Every other failure (TLS error, early close, deadline, full slots) is a retryable "can't reach the Mac", with backoff.
  - Certificate names and dates mean nothing.
- **Resumption, session tickets, False Start and renegotiation are off.** Every connection is a full handshake.
- **The `.ready` gate** (`CompanionSessionFacts.verified`) fails closed. It requires all of these:
  - TLS 1.3;
  - a peer certificate (a resumed session would present none);
  - no early data;
  - a 32-byte exporter (`EXPORTER-netmonitor-companion`, context `netmonitor companion v2`).
- **The phone sends nothing until the Mac's `serverHello` arrives.** In TLS 1.3 the client is ready before the server has judged the client's certificate.
- TLS 1.3 with an external PSK was tested first and fails in Network.framework. TLS 1.2 PSK was rejected in review.

### Keys and storage

| Where | What | Keychain item |
|---|---|---|
| Mac | Its identity key | `com.netmonitor.companion` / `identity`, AfterFirstUnlockThisDeviceOnly |
| Mac | One item per paired phone: pin, name, date paired | `com.netmonitor.companion` / `phone.<pin hex>` |
| iPhone | The paired Mac (ID, name, pin, host) and this phone's identity key for that pairing | `com.netmonitor.companion.mac` / `paired-mac`, WhenUnlockedThisDeviceOnly |

All items use the data protection keychain (`kSecUseDataProtectionKeychain`) and are never synchronised. On macOS that needs the app's own `keychain-access-groups` entry (`$(AppIdentifierPrefix)com.netmonitor.NetMonitor`), which also makes signing embed the application identifier. Without it, a signed Debug build gets `errSecMissingEntitlement` and the companion service stays off. An unsigned test host skips the Keychain tests for the same reason. Every status is checked. The phone makes a **new identity for every pairing**, so nothing links one pairing to the next. Pins are never logged.

### Pairing

1. **The Mac opens a pairing window** (Settings → Companion → Pair iPhone…). It holds two one-time secrets, the QR's 256 bits and a typed code. The window lasts 10 minutes on a monotonic clock and admits at most 8 pairing connections.
   - **QR text:** `netmonitor://pair?v=2&m=<mac UUID>&n=<name>&pin=<Mac pin, base64url>&k=<secret, base64url>&h=<host>&p=<port>`.
   - **Typed code:** 25 Crockford base32 digits = **125 bits** (a big-endian integer held in 16 bytes, top 3 bits zero, most significant digit first), plus Crockford's mod-37 check symbol (`0-9A-Z` without `ILOU`, then `*~$=U`). It is shown in groups of five. Input ignores case, dashes and spaces, and reads I/L as 1 and O as 0.
2. **The phone connects with a fresh identity.** From a QR, it pins the Mac's key from the QR. With a typed code it can't know the key yet, so it accepts the certificate provisionally.
3. **At `.ready`, the Mac makes the link a pairing link** if the window can still admit it. Only `pairRequest` and the phone's verdict (`pairResult` from the phone) are accepted, and frames are capped at 4 KiB. The Mac's `serverHello{mode: pairing, commitment}` commits to a fresh 32-byte nonce: `commitment = SHA-256("netmonitor commit v2" ‖ macNonce)`. A phone refuses a pairing hello without one.
4. **Phone → Mac:** `pairRequest{kind, proof, nonce, phoneName}`, where `nonce` is the phone's own 32 random bytes.
   - `proof = HMAC-SHA256(HKDF(secret, salt "netmonitor pairing v2", info "proof <kind>"), "netmonitor pair v2 phone" ‖ exporter ‖ macPin ‖ phonePin)`.
   - The Mac verifies the proof, then consumes the window, both in one critical section with no suspension in between. Both secrets burn together, and the window's other connections close. A wrong proof closes the link without burning the window. A pin that is already paired is refused.
5. **Mac → phone:** `pairChallenge{proof, nonce}`, the same HMAC with role `mac`, plus the Mac's nonce, revealed only now. The phone checks the proof, so a device that doesn't know the secret can't pose as the Mac. It also checks the nonce against the commitment.
6. **Both screens show a 6-digit comparison code**, HKDF(exporter, "netmonitor compare v2" ‖ macPin ‖ phonePin ‖ macNonce ‖ phoneNonce) mod 10⁶.
   - **The commit-then-reveal is what makes the code safe.** A TLS 1.3 exporter is fixed before the client's certificate is sent, so without the nonces a party in the middle holding a stolen code could grind its own key offline until the codes collide.
   - With them, neither side can choose its input after seeing the other's. A valid `pairRequest` burns the window, so an attacker in the middle gets one 1-in-10⁶ guess per window.
7. **The user confirms on both screens, in either order.**
   - On the phone, They Match sends `pairResult{accepted: true}` to the Mac; Don't Match sends `accepted: false` and ends pairing.
   - On the Mac, the user clicks Pair or Don't Pair.
8. **The Mac saves the phone's pin only after both confirmations,** and only if the Keychain saves it. Then it trusts the pin and sends `pairResult{accepted: true}`. Don't Pair, Don't Match or a failed save sends `accepted: false` (or just closes), and no pin exists on either side.
9. **The phone saves the Mac** (ID, name, pin from this session, identity key) on the Mac's `accepted: true`, which can only come after its own They Match. It then reconnects as paired.

Names are display only and never a basis for trust.

### Authorisation on the Mac

Each link gets a role at `.ready` from `CompanionTrustGate.classify`: `paired(pin, generation)` or `pairing(window)`. A link without a role reads and sends nothing. `CompanionLinkAuthorizer` decides every frame:

| Role | Accepted |
|---|---|
| none | nothing |
| pairing | `pairRequest` only |
| paired | everything the phone sends, except the pairing frames; `unpair` removes the phone; unknown types are ignored |

Before each dispatch, and again before a reply goes out, the Mac checks that the link's role still stands. A paired link stays authorised only under the credential generation it bound with.

### Limits

- At most 16 links, 8 of them still in the TLS handshake (reserved at accept), and 4 pairing links. A paired phone's link never counts against the pairing cap, so strangers can't lock it out once its TLS is up.
- A link must have a verified session within 10 s of accept. A pairing link gets 120 s, since it waits for the users.
- At most 2 model requests running per link; more get `busy`.
- One receive per link at a time, so no queue builds up.
- **Residual risk:** a LAN attacker can hold the 4 pre-auth slots and keep a phone or a pairing attempt out. It can't read or command anything.

### Revocation

- **Remove on the Mac:**
  - the pin is denied in memory at once;
  - the phone's links close;
  - then the Keychain item is deleted.
  - If the delete fails, the pin stays denied: it is kept in defaults and retried at each launch, and Settings reports it.
  - Deferred work for that phone checks its credential generation when it starts, so queued work never reaches the handler, and closing the link cancels it.
  - The phone's next connection gets `serverHello{refused}`. It shows "Forget This Mac, then pair again" and stops retrying.
- **Forget This Mac on the iPhone:** sends `unpair`, which removes the phone on the Mac, then deletes the phone's key. If the delete fails, the phone says so and keeps a "pending forget" mark that stops the credential loading or being used; it retries the delete at each load.
- **Can't be undone:** an operation already started before a revoke runs to completion: a Wake on LAN packet sent, a scan running, a model request submitted. Its reply isn't sent to a revoked link.

### Old and unpaired peers

A v1 phone speaks plain TCP, so its connection fails in the Mac's TLS handshake, and it keeps retrying. The Mac's Settings notes "a device that isn't paired tried to connect" only for a v2 device whose certificate the Mac doesn't trust, which it refused over the verified session. Neither a failed handshake nor a paired phone dropping off the network is reported. A v2 phone shows "Needs a NetMonitor update" for a Mac without TXT `pv=2`, and "Not paired" for a Mac it hasn't paired with. Release both apps together.

### Not covered

- Remote access beyond the LAN.
- A compromised device.
- iOS 18 / macOS 15 runtime behaviour, verified only on 27.2 runtimes so far (release gate #600).

## Message Format

Each message is JSON-encoded with a consistent structure:

```json
{
    "protocolVersion": 2,
    "type": "<message_type>",
    "payload": { ... }
}
```

Messages are sent as **4-byte big-endian length-prefixed JSON**: a `UInt32` byte count in
network (big-endian) order, followed by exactly that many bytes of JSON payload. There is no
delimiter between frames — the length prefix is what marks where one frame ends and the next
begins. A frame whose declared length exceeds `CompanionFrameDecoder.defaultMaximumFrameSize`
(1 MiB / 1,048,576 bytes) is rejected and the receiver's buffer is reset. Both sides implement
this framing via `CompanionFrameDecoder` (incoming) and `CompanionMessage.encodeLengthPrefixed()`
(outgoing), both defined in NetMonitorCore, so macOS and iOS share one implementation.

### Encoding/Decoding (Swift)

```swift
// Encode (adds the 4-byte length prefix)
let framedData = try message.encodeLengthPrefixed()

// Decode (from a reassembled, unprefixed JSON payload)
let message = try CompanionMessage.decode(from: jsonData)
```

Both `encodeLengthPrefixed()` and `decode(from:)` use a plain `JSONEncoder()`/`JSONDecoder()`
(`CompanionMessage.jsonEncoder` / `.jsonDecoder`) — no custom date strategy is set, so `Date`
fields use Foundation's default (seconds since the reference date, as a JSON number).

---

## Message Types

### 1. statusUpdate

Sent by the macOS app to report current monitoring status. Pushed automatically when status changes.

**Direction:** macOS → Companion

**Payload:**

| Field | Type | Description |
|-------|------|-------------|
| `isMonitoring` | Boolean | Whether monitoring is currently active |
| `onlineTargets` | Integer | Number of reachable targets |
| `offlineTargets` | Integer | Number of unreachable targets |
| `averageLatency` | Double? | Average latency in milliseconds (null if no data) |
| `timestamp` | ISO8601 Date | When this status was generated |

**Example:**

```json
{
    "type": "statusUpdate",
    "payload": {
        "isMonitoring": true,
        "onlineTargets": 4,
        "offlineTargets": 1,
        "averageLatency": 23.5,
        "timestamp": "2026-01-14T15:30:00Z"
    }
}
```

---

### 2. targetList

Sent by the macOS app with the current list of monitoring targets and their status.

**Direction:** macOS → Companion

**Payload:**

| Field | Type | Description |
|-------|------|-------------|
| `targets` | Array&lt;TargetInfo&gt; | List of all configured targets |

**TargetInfo Object:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique target identifier |
| `name` | String | Display name |
| `host` | String | Hostname or IP address |
| `port` | Integer? | Port number (null for ICMP) |
| `protocol` | String | One of: `icmp`, `http`, `https`, `tcp` |
| `isEnabled` | Boolean | Whether target is being monitored |
| `isReachable` | Boolean? | Current reachability (null if not yet checked) |
| `latency` | Double? | Latest latency in milliseconds |

**Example:**

```json
{
    "type": "targetList",
    "payload": {
        "targets": [
            {
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "name": "Cloudflare DNS",
                "host": "1.1.1.1",
                "port": null,
                "protocol": "icmp",
                "isEnabled": true,
                "isReachable": true,
                "latency": 12.3
            },
            {
                "id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
                "name": "Google",
                "host": "google.com",
                "port": 443,
                "protocol": "https",
                "isEnabled": true,
                "isReachable": true,
                "latency": 45.7
            }
        ]
    }
}
```

---

### 3. deviceList

Sent by the macOS app with discovered local network devices.

**Direction:** macOS → Companion

**Payload:**

| Field | Type | Description |
|-------|------|-------------|
| `devices` | Array&lt;DeviceInfo&gt; | List of discovered devices |

**DeviceInfo Object:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique device identifier |
| `ipAddress` | String | IPv4 address |
| `macAddress` | String | MAC address (format: `AA:BB:CC:DD:EE:FF`) |
| `hostname` | String? | Resolved hostname |
| `vendor` | String? | Hardware vendor from OUI lookup |
| `deviceType` | String | One of: `unknown`, `router`, `computer`, `phone`, `tablet`, `tv`, `speaker`, `printer`, `camera`, `iot` |
| `isOnline` | Boolean | Whether the device answered the Mac's latest scan, which is recent (#583, #598) |
| `members` | Array&lt;MemberInfo&gt;? | Since #594 PR2: every interface of the device (one entry per device; `ipAddress` and `macAddress` above are the current interface's). Absent from older Macs |
| `isDeviceOnline` | Boolean? | Since #594 PR2: what the Mac shows, online when any interface is online within grace. Absent from older Macs |

**MemberInfo Object** (#594 PR2):

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | The interface's row ID on the Mac |
| `ipAddress` | String | The interface's IPv4 address |
| `macAddress` | String? | Its MAC address, when it has a real one |
| `lastSeen` | Date | When the interface last answered a Mac scan |
| `answeredLatestScan` | Boolean | Whether it answered the Mac's latest scan of the network |
| `scanTime` | Date? | When that scan was reconciled, on the Mac's clock; nil when the Mac has none |
| `scanAge` | Number? | Seconds between that scan and sending this list, on the Mac's clock (#619) |

The iPhone counts an interface as a sighting only when it answered the Mac's latest scan and that scan is newer than the phone's own last scan. It places the Mac's scan on its own clock as `receivedAt - scanAge`, so the two clocks are never compared. It never groups interfaces on the Mac's word: grouping needs its own Bonjour evidence. Both directions are compatible: an older phone ignores the new keys, and a newer phone reads a list without them as one address per device.

**Example:**

```json
{
    "type": "deviceList",
    "payload": {
        "devices": [
            {
                "id": "123e4567-e89b-12d3-a456-426614174000",
                "ipAddress": "192.168.1.1",
                "macAddress": "A4:83:E7:12:34:56",
                "hostname": "router.local",
                "vendor": "Apple Inc.",
                "deviceType": "router",
                "isOnline": true
            },
            {
                "id": "987fcdeb-51a2-3b4c-d5e6-f7890abcdef1",
                "ipAddress": "192.168.1.42",
                "macAddress": "DC:A6:32:AB:CD:EF",
                "hostname": "raspberrypi.local",
                "vendor": "Raspberry Pi Foundation",
                "deviceType": "computer",
                "isOnline": true
            }
        ]
    }
}
```

---

### 4. command

Sent by companion apps to request actions from the macOS app.

**Direction:** Companion → macOS

**Payload:**

| Field | Type | Description |
|-------|------|-------------|
| `action` | String | Command action (see table below) |
| `parameters` | Object? | Optional key-value parameters |

**Available Actions:**

| Action | Description | Parameters |
|--------|-------------|------------|
| `startMonitoring` | Start monitoring all enabled targets | None |
| `stopMonitoring` | Stop monitoring | None |
| `scanDevices` | Trigger a network device scan | None |
| `ping` | Ping a host | `host`: target hostname/IP |
| `traceroute` | Run traceroute | `host`: target hostname/IP |
| `portScan` | Scan ports on a host | `host`: target, `ports`: port range (e.g., "1-1024") |
| `dnsLookup` | Perform DNS lookup | `host`: domain name, `type`: record type (A, AAAA, MX, etc.) |
| `wakeOnLan` | Send Wake-on-LAN packet | `mac`: MAC address |
| `refreshTargets` | Request updated target list | None |
| `refreshDevices` | Request updated device list | None |

**Examples:**

```json
{
    "type": "command",
    "payload": {
        "action": "startMonitoring",
        "parameters": null
    }
}
```

```json
{
    "type": "command",
    "payload": {
        "action": "ping",
        "parameters": {
            "host": "8.8.8.8"
        }
    }
}
```

```json
{
    "type": "command",
    "payload": {
        "action": "wakeOnLan",
        "parameters": {
            "mac": "A4:83:E7:12:34:56"
        }
    }
}
```

---

### 5. toolResult

Sent by the macOS app with results from tool commands (ping, traceroute, etc.).

**Direction:** macOS → Companion

**Payload:**

| Field | Type | Description |
|-------|------|-------------|
| `tool` | String | Tool name that produced this result |
| `success` | Boolean | Whether the operation succeeded |
| `result` | String | Human-readable result text |
| `timestamp` | ISO8601 Date | When the result was generated |

**Example:**

```json
{
    "type": "toolResult",
    "payload": {
        "tool": "ping",
        "success": true,
        "result": "PING 8.8.8.8: 64 bytes, icmp_seq=1, ttl=117, time=12.3ms\nPING 8.8.8.8: 64 bytes, icmp_seq=2, ttl=117, time=11.8ms\n\n--- 8.8.8.8 ping statistics ---\n2 packets transmitted, 2 received, 0% packet loss\nround-trip min/avg/max = 11.8/12.0/12.3 ms",
        "timestamp": "2026-01-14T15:32:45Z"
    }
}
```

---

### 6. error

Sent by the macOS app when an error occurs processing a command.

**Direction:** macOS → Companion

**Payload:**

| Field | Type | Description |
|-------|------|-------------|
| `code` | String | Error code for programmatic handling |
| `message` | String | Human-readable error description |
| `timestamp` | ISO8601 Date | When the error occurred |

**Error Codes:**

| Code | Description |
|------|-------------|
| `INVALID_COMMAND` | Unknown or malformed command |
| `INVALID_PARAMETERS` | Missing or invalid command parameters |
| `OPERATION_FAILED` | Command execution failed |
| `NOT_AVAILABLE` | Requested feature not available |
| `PERMISSION_DENIED` | Insufficient permissions |

**Example:**

```json
{
    "type": "error",
    "payload": {
        "code": "INVALID_PARAMETERS",
        "message": "Missing required parameter: host",
        "timestamp": "2026-01-14T15:33:00Z"
    }
}
```

---

### 7. heartbeat

Sent periodically to maintain connection and verify connectivity.

**Direction:** Bidirectional (macOS ↔ Companion)

**Payload:**

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | ISO8601 Date | Current time |
| `version` | String | Protocol version |
| `capabilities` | [String]? | Optional. What the sender does beyond the base protocol. The Mac sends `"insight.v1"` while its on-device model can answer, it isn't scanning, and "Answer model requests from iPhone" is on. That setting is **off by default** (#457). Since #590 only a paired iPhone can send model requests at all. Omitted when empty; older builds ignore it. |

The Mac sends a heartbeat when a client connects and in reply to each heartbeat, so a phone learns the Mac's capabilities at once and again every interval.

**Example:**

```json
{
    "type": "heartbeat",
    "payload": {
        "timestamp": "2026-01-14T15:35:00Z",
        "version": "1.0",
        "capabilities": ["insight.v1"]
    }
}
```

---

### 8. insightRequest

Asks the Mac's on-device model to word an insight for a phone that can't run the model (#457).

**Direction:** Companion → macOS, only to a Mac whose latest heartbeat listed `"insight.v1"`. Older Macs never advertise it, so they never receive this type.

**Payload:**

| Field | Type | Description |
|-------|------|-------------|
| `requestID` | UUID | Echoed in the response |
| `kind` | String | `explanation`, `summary`, `notification` or `advice`. The Mac takes its instructions from the kind, never from the wire; an unknown kind is answered `refused`. |
| `subject` | String | What was measured |
| `facts` | [String] | The measured values |
| `observations` | [String] | The app's computed key points |

The encoded payload is capped at 64 KiB (`InsightRequestPayload.maximumEncodedSize`). The phone doesn't send a larger request, and the Mac answers one with `tooLarge`.

### 9. insightResponse

The Mac's whole answer to one `insightRequest`, after its own grounding and text checks. Nothing is streamed.

**Direction:** macOS → Companion, only in reply to an `insightRequest`.

**Payload:**

| Field | Type | Description |
|-------|------|-------------|
| `requestID` | UUID | The request answered |
| `answer` | String? | The checked answer; absent on failure |
| `failure` | String? | `unavailable`, `refused`, `timeout`, `tooLarge` or `busy`. A reason the phone doesn't know reads as `refused`. `refused` and `tooLarge` are lasting for that request; `unavailable`, `timeout` and `busy` are for now, and the phone asks again later instead of remembering the failure. |

The Mac answers one request at a time (`busy` for another one meanwhile, and during a Mac scan) and gives the model 20 s. While it scans it also stops listing `insight.v1` and sends a heartbeat without it, and another when the scan ends. The phone gives up after 25 s, and at once when the link drops; the feature then falls back to its path without the model. Phone features that wait for a summary wait at least 27 s when the Mac writes it; notification bodies keep their 2 s budget.

The phone sends requests only after the user agrees, once, to "Use your Mac for on-device AI?"; a Settings switch changes the answer.

---

## Communication Flow

### Initial Connection

```
Companion                              macOS
    |                                    |
    |==== [TLS 1.3, mutual pins] =======>|
    |<------- [serverHello: paired] -----|
    |<------- [heartbeat] ---------------|
    |-------- [networkProfile] -------->|
    |                                    |
    |<------- [statusUpdate] ------------|
    |<------- [targetList] --------------|
    |<------- [deviceList] --------------|
    |                                    |
```

### Command/Response

```
Companion                              macOS
    |                                    |
    |-------- [command: ping] --------->|
    |                                    |
    |<------- [toolResult] --------------|
    |                                    |
```

### Error Handling

```
Companion                              macOS
    |                                    |
    |-------- [command: invalid] ------>|
    |                                    |
    |<------- [error] ------------------|
    |                                    |
```

### Pairing (#590)

```
Companion                              macOS
    |==== [TLS 1.3, phone key unknown] =>|   (a pairing window is open)
    |<------- [serverHello: pairing] ----|
    |-------- [pairRequest] ----------->|
    |<------- [pairChallenge] ----------|
    |     both screens: comparison code  |   user confirms on the Mac
    |<------- [pairResult: accepted] ---|
    |==== [reconnect as paired] =======>|
```

### Insight (#457)

```
Companion                              macOS
    |<------- [heartbeat: insight.v1] ---|
    |-------- [insightRequest] -------->|
    |<------- [insightResponse] --------|
```

### Keepalive

```
Companion                              macOS
    |                                    |
    |-------- [heartbeat] ------------->|
    |<------- [heartbeat] --------------|
    |                                    |
```

---

## Implementation Notes

### Date Encoding

All dates use ISO 8601 format with timezone: `2026-01-14T15:30:00Z`

### MAC Address Format

MAC addresses use uppercase colon-separated format: `AA:BB:CC:DD:EE:FF`

### Protocol Versions

| Version | Description |
|---------|-------------|
| `1` | Initial release with Phase 3: plain TCP |
| `2` | TLS 1.3 with mutually pinned identities and pairing (#590). A v1 peer can't connect |

### Recommended Heartbeat Interval

Send heartbeat messages every 30 seconds to maintain connection state.

### Message Size Limits

Individual messages should not exceed 1 MB. For large datasets, pagination may be implemented in future versions.

### Unknown Message Types

A frame whose `type` a build doesn't know decodes as `CompanionMessage.unknown(type:)` and is ignored by both sides; the connection stays open and no reply is sent. Builds before #457 failed to decode such a frame instead: they dropped it, kept the connection, and the Mac replied with an `error` (`DECODE_ERROR`). New types are therefore still sent only to a peer that advertised them in `capabilities`. The exception is #590's deliberate bump to `protocolVersion` 2: the transport itself changed, so a v1 peer can't connect at all.

---

## Swift Types Reference

The protocol is defined in the `NetMonitorShared` framework:

```swift
import NetMonitorShared

// Message types
CompanionMessage          // Root enum
StatusUpdatePayload       // Monitoring status
TargetListPayload         // Target list
TargetInfo                // Individual target
DeviceListPayload         // Device list
DeviceInfo                // Individual device
CommandPayload            // Command request
CommandAction             // Command enum
ToolResultPayload         // Tool output
ErrorPayload              // Error response
HeartbeatPayload          // Keepalive, with optional capabilities
InsightRequestPayload     // Insight request (#457)
InsightResponsePayload    // Insight answer or failure reason (#457)
ServerHelloPayload        // Mac's greeting: paired, pairing or refused (#590)
PairRequestPayload        // Phone's proof of the one-time secret (#590)
PairChallengePayload      // Mac's proof of the same secret (#590)
PairResultPayload         // Mac → phone: paired or not; phone → Mac: the codes match or not (#590)
UnpairPayload             // The phone forgot this Mac (#590)
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-14 | Initial protocol specification |
| 1.0 | 2026-11-24 | Optional heartbeat `capabilities`; `insightRequest` / `insightResponse` behind `insight.v1` (#457). Wire version unchanged. |
| 2 | 2026-11-25 | TLS 1.3 with mutually pinned identities; pairing by QR or typed code with a comparison code; `serverHello`, `pairRequest`, `pairChallenge`, `pairResult`, `unpair`; TXT `pv` and `mac` (#590). |
