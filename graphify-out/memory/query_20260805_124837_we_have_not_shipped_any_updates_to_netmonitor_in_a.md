---
type: "query"
date: "2026-08-05T12:48:37.977856+00:00"
question: "we have not shipped any updates to netmonitor in a while.  Please do an architectual review of buth the ios and mac app and find areas to improve performance and stability and user experience. Then submit a propopsal for a new release"
contributor: "graphify"
outcome: "useful"
source_nodes: ["ScanEngine", "DeviceDiscoveryService", "ConnectionBudget", "ScanAccumulator", "TCPProbeScanPhase", "ServiceProtocols.swift"]
---

# Q: we have not shipped any updates to netmonitor in a while.  Please do an architectual review of buth the ios and mac app and find areas to improve performance and stability and user experience. Then submit a propopsal for a new release

## Answer

Expanded from original query via graph vocab: [scan, engine, service, error, network, concurrency, monitor, device, testing, latency, cache, persist]. The shared graph identified ScanEngine, DeviceDiscoveryService, ConnectionBudget, ScanAccumulator, TCPProbeScanPhase, and ServiceProtocols.swift as the central scan and service seams. Repository review found the release should prioritize once-only iOS background registration, end-to-end cancellation and hard timeout behavior, cancellation-aware connection budgeting, explicit SwiftData recovery, batched persistence and progress publication, bounded queries, companion transport isolation, and clearer UX states. A focused v2.2.1 Reliability and Responsiveness epic was submitted as GitHub issue 262; full macOS scan-stack convergence is deferred to 2.3.

## Outcome

- Signal: useful

## Source Nodes

- ScanEngine
- DeviceDiscoveryService
- ConnectionBudget
- ScanAccumulator
- TCPProbeScanPhase
- ServiceProtocols.swift