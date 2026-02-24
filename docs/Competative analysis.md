# Competitive Analysis: Feature Opportunities for NetMonitor
## What You Already Have (Strong Position)
Your tools coverage is solid: Ping, Traceroute, Port Scanner, DNS Lookup, WHOIS, Speed Test, Wake on LAN, Bonjour Browser, device discovery (multi-phase: ARP + TCP + Bonjour + SSDP + ICMP), network map, target monitoring with statistics, Mac↔iOS companion protocol, widgets, notifications.
**You match or exceed** LanScan, basic iNet, and Network Analyzer on core scanning. You're competitive with Fing on discovery.
---
## 🔴 High-Value Gaps (Competitors monetize these heavily)
| # | Feature | Who Has It | Value Proposition |
|---|---------|-----------|-------------------|
| 1 | **Bandwidth/Traffic Per Device** | GlassWire, Little Snitch, Fing Premium | Users' #1 ask on r/macapps. "Which device is hogging my bandwidth?" Track per-device data usage over time with anomaly detection. |
| 2 | **Network Timeline / Event History** | GlassWire | Visual timeline showing device connect/disconnect, traffic spikes, network changes. Historical lookback. GlassWire's signature feature. |
| 3 | **Device Blocking & Internet Time Limits** | Fing Desktop (Premium) | Block unauthorized devices, schedule internet access per device/user. Fing's top premium feature. Requires ARP spoofing or router API. |
| 4 | **Router Vulnerability Assessment** | Fing Premium | Automated security scan of router — open ports, known CVEs, default credentials, UPnP exposure. Security-conscious users love this. |
| 5 | **WiFi Heatmapping** | NetSpot ($150+) | Walk-around survey that maps signal strength to a floorplan. NetSpot charges premium for this. macOS has CoreWLAN APIs for signal data. |
| 6 | **Network Health Score** | Fing | Single "network score" combining security, speed, device count, and configuration quality. Great at-a-glance metric for the dashboard. |
## 🟡 Medium-Value Gaps (Differentiation opportunities)
| # | Feature | Who Has It | Value Proposition |
|---|---------|-----------|-------------------|
| 7 | **GeoTrace (Visual Traceroute on Map)** | Network Tools AI | Plot traceroute hops on a world map. Gorgeous visualization — your existing traceroute + MapKit. Low effort, high wow-factor. |
| 8 | **SSL Certificate Monitor** | Network Tools AI (subscription) | Track cert expiration for your domains/services. Alert before they expire. Devs and sysadmins pay for this. |
| 9 | **Domain Expiration Monitor** | Network Tools AI (subscription) | Same concept — track domain registration renewal dates. |
| 10 | **Hidden Camera / Rogue Device Detection** | Fing | Scan for devices matching known camera vendors/patterns. Very popular consumer feature for travel. |
| 11 | **DNS Propagation Checker** | Network Tools AI | Check DNS records across worldwide resolvers. Useful for domain migration. Could use public DNS APIs. |
| 12 | **IP/Domain Reputation & Blacklist Check** | Network Tools AI | Check if your IP is on email RBLs or blacklists. Useful for self-hosted mail servers. |
| 13 | **Application-Level Connection Monitoring** | Little Snitch ($49) | See which *apps* are connecting where. Per-app firewall rules. Little Snitch's entire business. Requires Network Extension on macOS. |
| 14 | **Scheduled/Automated Scans** | Fing, various | Auto-scan on schedule or when joining a new network. Alert on changes. Your notification service already exists — just need triggers. |
## 🟢 Low-Effort / Quick Wins
| # | Feature | Who Has It | Value Proposition |
|---|---------|-----------|-------------------|
| 15 | **Subnet Calculator** | iNet, many tools | CIDR calculator, network/broadcast address, usable IPs. Trivial to build, rounds out the tools tab. |
| 16 | **VPN Detection & Info** | Listed in your macOS PRD "Future" | Detect active VPN, show tunnel interface details. NWPathMonitor already provides some of this. |
| 17 | **AR WiFi Signal View** (iOS) | Network Tools AI | Camera overlay showing signal strength in real-time. iOS ARKit + CoreLocation. Flashy demo feature. |
| 18 | **Live Activities** (iOS) | Listed in your iOS PRD "Future" | Dynamic Island + lock screen for ongoing scans/monitoring. Already in your roadmap. |
| 19 | **Shortcuts/Siri Integration** (iOS) | Listed in your iOS PRD "Future" | "Hey Siri, scan my network" / automation triggers. Already in your roadmap. |
| 20 | **World Ping** | Network Utilities | Ping target from multiple global locations. Can use public APIs (check-host.net, etc.). |
| 21 | **Export Reports as PDF** | Fing Premium | Formatted network reports with branding. Shareable with clients/ISPs. |
---
## Top Recommendations Selected for Roadmap
1. **GeoTrace (Visual Traceroute on Map)** — You already have traceroute. Add MapKit overlay with hop geolocation. Highest wow-per-effort ratio. Works on both platforms.
2. **Network Timeline / Event History** — Log every network event (device join/leave, speed changes, connectivity drops) on a scrollable timeline. Differentiates from every competitor except GlassWire.
3. **Network Health Score** — Composite score on the dashboard combining: security, performance, device count, WiFi signal quality. Easy to compute from data you already collect.
4. **Scheduled Scans + Change Detection** — Auto-scan periodically, diff against previous results, alert on new/missing devices.
5. **SSL/Domain Expiration Monitor** — Query SSL certs and WHOIS for expiration dates. Set up alerts. Subscription-worthy feature for the power-user segment.
6. **WiFi Heatmapping** — Walk-around survey that maps signal strength to a floorplan (iOS) and creates a heatmap of coverage. Very premium feature.