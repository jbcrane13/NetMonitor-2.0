# Agent Readiness — Session 3: Code Quality Analysis

**Date:** 2026-02-28
**Commits:** `8708ff3` (pushed to main)
**Criteria addressed:** 5
**Score movement:** ~69% → ~79% (approaching Level 5)

---

## What Was Implemented

### Dead Code Detection — Periphery

**Tool:** [Periphery](https://github.com/peripheryapp/periphery) — Swift-native unused declaration scanner

**Configuration:** `.periphery.yml`

Key settings:
- Scans both `NetMonitor-macOS` and `NetMonitor-iOS` schemes
- `retain_public: true` — shared package public APIs are not flagged
- `retain_codable_properties: true` — SwiftData/Codable runtime-accessed properties retained
- `retain_swift_ui_previews: true` — preview providers not flagged
- `retain_objc_annotated: true` — ObjC interop retained
- Test files excluded from reporting (mocks/helpers look unused by design)

**Baseline:** 117 warnings found at initial scan. These represent real candidates for cleanup — unused properties, dead enum cases, unused parameters, and redundant imports. They are tracked but not blocking.

**CI job:** `code-quality.yml → dead-code` — warning-only, annotates PRs via `--format github-actions`. Does not block merges.

**To suppress a legitimate false positive:**
```swift
// periphery:ignore
func protocolRequirementCalledAtRuntime() { ... }
```
File a beads issue before removing real dead code.

**Local run:**
```bash
periphery scan --quiet              # Full report
periphery scan --quiet --format xcode  # Xcode-clickable output
```

---

### Duplicate Code Detection — jscpd

**Tool:** [jscpd](https://github.com/kucherenko/jscpd) — polyglot copy-paste detector, Swift support via npm

**Configuration:** `.jscpd.json`

Settings:
- Language: `swift`
- Minimum tokens: 60
- Minimum lines: 6
- Threshold: 5% project duplication before warning
- Excludes: `build/`, `.build/`, test directories, `.xcodeproj/`

**CI job:** `code-quality.yml → duplicate-code` — warning-only, runs on `ubuntu-latest`. Does not block merges.

**To address duplicate code:** Extract shared logic into `NetMonitorCore` (accessible to both platforms) rather than duplicating across `NetMonitor-macOS/` and `NetMonitor-iOS/`.

**Local run:**
```bash
npm install -g jscpd   # one-time
jscpd --languages swift .
```

---

### Log Scrubbing

#### New: `NetMonitor-iOS/Platform/Logging.swift`

iOS now has the same structured `os.Logger` categories as macOS. Use these instead of `print()`:

| Category | Logger | Use for |
|----------|--------|---------|
| `companion` | `Logger.companion` | Mac↔iOS connection events |
| `discovery` | `Logger.discovery` | Device and Bonjour scan events |
| `monitoring` | `Logger.monitoring` | Target ping and uptime events |
| `data` | `Logger.data` | Persistence and SwiftData operations |
| `network` | `Logger.network` | Network interface and connectivity |
| `app` | `Logger.app` | App lifecycle and general events |
| `background` | `Logger.background` | BGTaskScheduler events |
| `geofence` | `Logger.geofence` | GeoFence trigger events |

#### New: `LogSanitizer` in `NetMonitorCore/Utilities/LogSanitizer.swift`

**Mandatory for all log statements involving network-identifying values.**

| Method | Redacts | Release output |
|--------|---------|----------------|
| `LogSanitizer.redactIP(_:)` | IPv4 host portion | `192.168.x.x` |
| `LogSanitizer.redactIPFull(_:)` | Full IPv4 address | `x.x.x.x` |
| `LogSanitizer.redactMAC(_:)` | Device-specific MAC octets | `AA:BB:CC:xx:xx:xx` |
| `LogSanitizer.redactHostname(_:)` | Hostname, keeps TLD | `*.local` |
| `LogSanitizer.redactSSID(_:)` | Full SSID | `<redacted-ssid>` |
| `LogSanitizer.redact(_:)` | Any string | `<redacted>` |
| `LogSanitizer.redactOptional(_:)` | Optional string | `<redacted>` or `(nil)` |

All methods pass values through unmodified in `DEBUG` builds. Redaction only applies in `Release` builds.

**Usage:**
```swift
Logger.network.debug("Gateway: \(LogSanitizer.redactIP(gatewayIP))")
Logger.discovery.info("Device MAC: \(LogSanitizer.redactMAC(macAddress))")
Logger.network.debug("SSID: \(LogSanitizer.redactSSID(ssid))")
Logger.network.debug("Host: \(LogSanitizer.redactHostname(hostname))")
```

**CI job:** `code-quality.yml → log-scrubbing` — greps for `Logger` calls containing known sensitive variable names (`ipAddress`, `macAddress`, `ssid`, `hostname`, `gatewayIP`) without a `LogSanitizer` wrapper. Warning-only.

---

### Automated Documentation Validation

**CI job:** `code-quality.yml → doc-freshness`

Two checks on every PR:

1. **Doc freshness** — verifies `README.md`, `AGENTS.md`, `docs/ADR.md`, and `docs/Companion-Protocol-API.md` have been updated within 180 days. Warns (non-blocking) on stale docs.

2. **Skill frontmatter** — verifies every `.factory/skills/*/SKILL.md` has both `name:` and `description:` YAML frontmatter. **Blocks** if missing (an agent creating a skill without frontmatter breaks skill discovery).

---

### Runbooks Documented

`AGENTS.md` now has a **Runbooks & Reference Docs** section with two tables:

**Architecture and reference docs:**

| Document | Location |
|----------|----------|
| Architecture Decision Records | `docs/ADR.md`, `docs/ADR-macOS.md` |
| Companion Protocol | `docs/Companion-Protocol-API.md` |
| Shared Codebase Plan | `docs/NETMONITOR-2.0-SHARED-CODEBASE-PLAN.md` |
| Testing Lessons Learned | `docs/TESTING-LESSONS-LEARNED.md` |
| SwiftUI Best Practices | `docs/SwiftUI Best Practices.md` |
| iOS PRD | `docs/NetMonitor iOS Companion - Product Requirements Document.md` |
| macOS PRD | `docs/NetMonitor for macOS - Product Requirements Document.md` |
| Coverage Gates | `docs/testing/coverage-gates.md` |

**Agent workflow runbooks (skills):**

| Skill | Purpose |
|-------|---------|
| `.factory/skills/run-tests/SKILL.md` | Run tests on mac-mini via SSH |
| `.factory/skills/check-coverage/SKILL.md` | Run and interpret coverage gates |
| `.factory/skills/create-release/SKILL.md` | End-to-end release procedure |
| `.factory/skills/fix-lint/SKILL.md` | Resolve SwiftLint and SwiftFormat failures |

---

## Criteria Fixed

| Criterion | Before | After |
|-----------|--------|-------|
| `dead_code_detection` | 0/2 | 2/2 |
| `duplicate_code_detection` | 0/2 | 2/2 |
| `log_scrubbing` | 0/2 | 2/2 |
| `automated_doc_generation` | 0/1 | 1/1 |
| `runbooks_documented` | 0/1 | 1/1 |

---

## Files Created / Modified

| File | Action |
|------|--------|
| `.periphery.yml` | Created |
| `.jscpd.json` | Created |
| `.github/workflows/code-quality.yml` | Created — dead-code, duplicate-code, log-scrubbing, doc-freshness jobs |
| `.github/AGENTS.md` | Modified — code-quality.yml added to workflow table |
| `NetMonitor-iOS/Platform/Logging.swift` | Created — iOS Logger category definitions |
| `Packages/NetMonitorCore/Sources/NetMonitorCore/Utilities/LogSanitizer.swift` | Created |
| `AGENTS.md` | Modified — Runbooks section + Logging Guidelines + Code Quality Tools table |

---

## Remaining Failing Items (skip or defer)

| Criterion | Recommendation |
|-----------|---------------|
| `devcontainer` | Skip — Xcode + Apple SDK cannot run in a container |
| `deps_pinned` | N/A — no external SPM dependencies exist to pin |
| `feature_flag_infrastructure` | Defer — requires LaunchDarkly or custom server; evaluate post-launch |
| `error_tracking_contextualized` | Defer — Sentry adds privacy obligations; revisit post-launch |
| `distributed_tracing` | Skip — not applicable to local desktop/mobile apps |
| `metrics_collection` | Skip — not applicable to local apps |
| `alerting_configured` | Skip — PagerDuty/OpsGenie are for server uptime |
| `product_analytics_instrumentation` | Defer — privacy consideration; post-launch decision |
| `error_to_insight_pipeline` | Defer — depends on error tracking being implemented first |
