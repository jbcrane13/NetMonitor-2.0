<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitorCore/Utilities

## Purpose
Shared utility functions for network calculations, service helpers, and scan state management.

## Key Files

| File | Description |
|------|-------------|
| `NetworkUtilities.swift` | IPv4 parsing, subnet math (CIDR to host range), IP address utilities |
| `ServiceUtilities.swift` | Shared service helpers (retry logic, timeout wrappers) |
| `ResumeState.swift` | Scan resume state tracking for crash recovery |

## For AI Agents

### Working In This Directory
- `NetworkUtilities.swift` is the canonical source for all IP/subnet math — do not duplicate elsewhere
- Functions here must be pure and `Sendable`-safe (no mutable shared state)
- `ResumeState` coordinates with `NetworkScanKit/ResumeState` — keep them in sync if modifying

<!-- MANUAL: -->
