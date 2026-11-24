# NetMonitor Companion Protocol API

This document describes the communication protocol between the NetMonitor macOS application and companion apps (iOS/iPadOS).

## Service Discovery

NetMonitor advertises itself via Bonjour (mDNS) for automatic discovery on the local network.

| Property | Value |
|----------|-------|
| Service Type | `_netmon._tcp` |
| Port | `8849` |
| Service Name | `NetMonitor` |

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

After discovering the service, establish a TCP connection to the advertised endpoint on port 8849.

### Connection Example (Swift)

```swift
let connection = NWConnection(to: endpoint, using: .tcp)
connection.stateUpdateHandler = { state in
    switch state {
    case .ready:
        // Connected - ready to send/receive messages
    case .failed(let error):
        // Handle connection failure
    default:
        break
    }
}
connection.start(queue: .main)
```

## Message Format

Each message is JSON-encoded with a consistent structure:

```json
{
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
| `isOnline` | Boolean | Whether device is currently reachable |

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
| `capabilities` | [String]? | Optional. What the sender does beyond the base protocol. The Mac sends `"insight.v1"` while its on-device model can answer and "Answer model requests from iPhone" is on. Omitted when empty; older builds ignore it. |

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
    |-------- [Connect to port 8849] --->|
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
| `1.0` | Initial release with Phase 3 |

### Recommended Heartbeat Interval

Send heartbeat messages every 30 seconds to maintain connection state.

### Message Size Limits

Individual messages should not exceed 1 MB. For large datasets, pagination may be implemented in future versions.

### Unknown Message Types

A frame whose `type` a build doesn't know decodes as `CompanionMessage.unknown(type:)` and is ignored by both sides; the connection stays open and no reply is sent. Builds before #457 failed to decode such a frame instead: they dropped it, kept the connection, and the Mac replied with an `error` (`DECODE_ERROR`). New types are therefore still sent only to a peer that advertised them in `capabilities`, and `protocolVersion` stays 1.

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
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-14 | Initial protocol specification |
| 1.0 | 2026-11-24 | Optional heartbeat `capabilities`; `insightRequest` / `insightResponse` behind `insight.v1` (#457). Wire version unchanged. |
