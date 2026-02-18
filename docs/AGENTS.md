<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# docs

## Purpose
Architecture documentation, product requirements, ADRs, and planning documents for the NetMonitor-2.0 monorepo. Not compiled — read-only reference for agents and contributors.

## Key Files

| File | Description |
|------|-------------|
| `NETMONITOR-2.0-SHARED-CODEBASE-PLAN.md` | Monorepo architecture rationale and goals (70% code overlap, 40% LOC reduction) |
| `Companion-Protocol-API.md` | Mac–iOS wire protocol spec (Bonjour `_netmon._tcp`, port 8849, newline-delimited JSON) |
| `ADR.md` | Architecture Decision Records for shared codebase decisions |
| `ADR-macOS.md` | macOS-specific architecture decisions |
| `SwiftUI Best Practices.md` | UI patterns and conventions enforced across both targets |
| `AppStore-Metadata.md` | App Store listing copy and metadata |
| `NetMonitor for macOS - Product Requirements Document.md` | macOS PRD |
| `NetMonitor iOS Companion - Product Requirements Document.md` | iOS PRD |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `plans/` | Dated implementation plans for each development phase (see `plans/AGENTS.md`) |

## For AI Agents

### Working In This Directory
- Do not modify docs unless explicitly asked; they are reference material
- When implementing the companion protocol, always consult `Companion-Protocol-API.md` for wire format details
- Check `SwiftUI Best Practices.md` before adding new UI patterns
- ADRs are append-only — never delete existing decisions, only add new ones

<!-- MANUAL: -->
