<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-01-28 | Updated: 2026-01-28 -->

# plans

## Purpose

This directory contains the implementation phase plans for NetMonitor macOS development. Each file documents the goals, tasks, and detailed implementation steps for a specific development phase. Plans follow a structured format to guide Claude Code agents through execution using the agent-driven development workflow.

**Key Characteristics:**
- Date-prefixed filenames (YYYY-MM-DD format)
- Markdown format with clear task-based structure
- Phase-based sequential development
- All 4 phases complete and deployed
- Reference design document included

## Key Files

| File | Phase | Purpose | Status |
|------|-------|---------|--------|
| `2026-01-10-netmonitor-macos-phase1-foundation.md` | Phase 1 | Xcode workspace setup, SwiftData models, NavigationSplitView shell, Swift 6 strict concurrency | Complete |
| `2026-01-10-netmonitor-macos-v1-design.md` | Design | Architecture design document, project structure, workspace layout, core patterns | Complete |
| `2026-01-11-netmonitor-macos-phase2-monitoring.md` | Phase 2 | Core monitoring engine: actor-based services, HTTPMonitorService, ICMPMonitorService, MonitoringSession coordinator, Dashboard | Complete |
| `2026-01-13-netmonitor-macos-phase3-discovery-menubar-companion.md` | Phase 3 | Device discovery (ARP/Bonjour), Menu bar integration, DeviceDiscoveryCoordinator, MAC vendor lookup, Companion protocol and service, WakeOnLan | Complete |
| `2026-01-17-phase4-tools-settings-icmp-design.md` | Phase 4 | Network tools UI (7 diagnostic tools), comprehensive settings (7 sections), shell-based ICMP monitoring, ShellCommandRunner, ProcessPingService | Complete |

## For AI Agents

### Working In This Directory

**Primary Task:** Implement a specific phase plan
1. Read the phase plan file (e.g., `2026-01-11-netmonitor-macos-phase2-monitoring.md`)
2. Review the Design reference (`2026-01-10-netmonitor-macos-v1-design.md`)
3. Execute tasks in sequential order with full verification
4. Use agent-driven development workflow: plan → implement → verify → commit
5. Update project CLAUDE.md with completion status

**For Specific Implementation:**
- Each phase file contains numbered Tasks (Task 1, Task 2, etc.)
- Tasks contain detailed Steps with code examples where applicable
- Files to create/modify are explicitly listed at task start
- Code examples provided are starting points - adapt to current codebase

### Phase Planning and Structure

**Phase 1: Foundation** (`2026-01-10-netmonitor-macos-phase1-foundation.md`)
- Goal: Establish project structure with SwiftData models and UI shell
- Key Deliverables: Xcode project, SwiftData models (NetworkTarget, TargetMeasurement, LocalDevice, SessionRecord), NavigationSplitView
- Output: Working Xcode project with proper concurrency setup

**Phase 2: Core Monitoring** (`2026-01-11-netmonitor-macos-phase2-monitoring.md`)
- Goal: Implement monitoring engine with real-time updates
- Key Deliverables: NetworkMonitorService protocol, HTTPMonitorService, MonitoringSession coordinator (@MainActor), Dashboard view
- Output: Real-time target monitoring with persistent measurement history

**Phase 3: Discovery & Companion** (`2026-01-13-netmonitor-macos-phase3-discovery-menubar-companion.md`)
- Goal: Add device discovery and companion app communication
- Key Deliverables: ARPScannerService, BonjourDiscoveryService, DeviceDiscoveryCoordinator, CompanionService, Menu bar UI
- Output: Local device discovery with Bonjour companion protocol

**Phase 4: Tools & Settings** (`2026-01-17-phase4-tools-settings-icmp-design.md`)
- Goal: Add comprehensive network tools and settings UI
- Key Deliverables: 7 diagnostic tools (Ping, Traceroute, PortScanner, DNSLookup, WHOIS, Bonjour Browser, WakeOnLan), 7 settings panels, ShellCommandRunner
- Output: Full-featured network utility suite

### Common Patterns

#### Task Structure
All tasks follow this pattern:
1. **Files:** Lists files to create/modify with locations
2. **Step 1, Step 2...:** Sequential numbered steps with code examples
3. **Expected:** Verification criteria and what to check

#### Service Implementation Pattern
```
1. Create protocol in Services/ (e.g., NetworkMonitorService.swift)
2. Implement as an actor for thread safety
3. Create tests in NetMonitorTests/Services/
4. Integrate with coordinator or main app
5. Add to CLAUDE.md implementation status
```

#### View Implementation Pattern
```
1. Create SwiftUI view file in Views/ or Views/Subtopic/
2. Use @Observable state or @Environment dependencies
3. Add accessibility identifiers for testing
4. Create supporting view models if needed
5. Include error handling and loading states
```

#### Protocol-Oriented Design
- Services are actors conforming to protocol contracts
- Views use @Environment for dependency injection
- @MainActor used for UI-bound coordinators
- Swift 6 strict concurrency enabled throughout

#### File Location Conventions
| Type | Location | Naming |
|------|----------|--------|
| Services | `NetMonitor/Services/` | `*Service.swift` or `*Coordinator.swift` |
| Models | `NetMonitor/Models/` | Singular noun (NetworkTarget, LocalDevice) |
| Views | `NetMonitor/Views/` | `*View.swift` |
| Tests | `NetMonitorTests/Services/` | `*Tests.swift` |
| Shared Code | `NetMonitorShared/Sources/NetMonitorShared/` | Protocol and shared types |

### Verification Checklist

For each completed task, verify:
- [ ] Files created in correct locations
- [ ] Code compiles without errors
- [ ] Swift 6 strict concurrency checks pass
- [ ] Tests written and passing
- [ ] Accessibility identifiers added (UI elements)
- [ ] Error handling implemented
- [ ] Code follows established patterns in CLAUDE.md

### Integration Points

**After each phase, integrate with:**
1. Update `/Users/blake/Projects/NetMonitor/CLAUDE.md` → Implementation Status section
2. Commit changes with conventional commit messages: `feat:`, `fix:`, `refactor:`
3. Document any deviations from plan in CLAUDE.md

**Cross-Phase Dependencies:**
- Phase 2 depends on Phase 1 completion
- Phase 3 depends on Phase 2 completion
- Phase 4 depends on Phase 3 completion
- All phases reference design document: `2026-01-10-netmonitor-macos-v1-design.md`

### Key Technologies and Frameworks

**Per Phase:**
| Phase | Primary Framework | Key Technologies |
|-------|-------------------|------------------|
| Phase 1 | SwiftUI, SwiftData | Xcode project setup, @Observable, NavigationSplitView |
| Phase 2 | AsyncStream, Actors | NetworkMonitorService protocol, URLSession, CFSocket |
| Phase 3 | Network.framework | NWConnection, NWBrowser, Bonjour, NWListener |
| Phase 4 | Process, Shell | ShellCommandRunner, Foundation.Process, pipe streams |

**Concurrency Model (Consistent Across All Phases):**
- Actors for all background services
- @MainActor for UI coordinators
- async/await for all async operations
- Swift 6 strict concurrency checking enabled
- Continuation-based adaptation for legacy APIs (CFSocket)

## Dependencies

**Between Plans:**
```
Phase 1 (Foundation)
    ↓
Phase 2 (Core Monitoring)
    ↓
Phase 3 (Device Discovery & Companion)
    ↓
Phase 4 (Tools & Settings)
```

**External Dependencies:**
- **macOS 15.0+** (Sequoia and later)
- **Xcode 16+** (Swift 6 support)
- **Swift Package Manager** (for NetMonitorShared package)
- **System frameworks:** Network, AppKit, Combine, MultipeerConnectivity

**Design Reference:**
All implementation phases reference the architecture design in `2026-01-10-netmonitor-macos-v1-design.md`. When questions arise about overall architecture or design decisions, consult this document.

---

<!-- MANUAL: This file documents the structure of phase plans for agent-driven development. Do not edit programmatically. -->
