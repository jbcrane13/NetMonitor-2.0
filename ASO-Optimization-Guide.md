# NetMonitor ASO Optimization Guide

*March 2026*

---

## How App Store Indexing Works (Quick Context)

Apple indexes exactly three metadata fields for search ranking: **Title** (30 chars), **Subtitle** (30 chars), and **Keywords** (100 chars, hidden). That gives you 160 total indexed characters. The description is NOT indexed — it's purely for conversion once someone lands on your page.

Key rules: never duplicate a word across these three fields (Apple counts it once regardless), use singular forms (Apple auto-pluralizes), no spaces after commas in the keyword field, and avoid filler words like "app" or "the."

---

## NetMonitor Mobile (iOS) — $4.99

### Current Metadata

| Field | Current | Chars |
|-------|---------|-------|
| Title | NetMonitor Mobile | 17/30 |
| Subtitle | Pro Network Tools. No Cloud. | 28/30 |
| Keywords | *(unknown)* | ?/100 |

### Problems with Current Metadata

**Title** — You're leaving 13 characters on the table. "Mobile" is a wasted keyword (nobody searches "mobile" when they're already on the iOS App Store). You should use those characters for high-value search terms.

**Subtitle** — "Pro Network Tools" is decent but "No Cloud" is a conversion message, not a search term. Nobody is searching "no cloud." That's better placed in your description's opening line where it already lives.

### Recommended Title Options

| Option | Title | Chars | Rationale |
|--------|-------|-------|-----------|
| **A (Recommended)** | NetMonitor: WiFi Scanner & Map | 30/30 | Hits "wifi," "scanner," and "map" — three of the highest-volume search terms in this category. Natural reading. |
| B | NetMonitor: Network Scanner | 27/30 | Cleaner, targets the #1 category keyword. Leaves 3 chars unused. |
| C | NetMonitor — WiFi & LAN Scanner | 31 ❌ | One char over — would need to drop the space around the dash. |

**My recommendation is Option A.** "WiFi Scanner" is the highest-volume phrase in this category (it's what Fing ranks for), and "Map" covers the network map / GeoTrace feature that differentiates you.

### Recommended Subtitle Options

| Option | Subtitle | Chars | Rationale |
|--------|----------|-------|-----------|
| **A (Recommended)** | Ping, Traceroute & Speed Test | 30/30 | Packs three high-search-volume tool names that aren't in the title. Natural, readable. |
| B | LAN Tools, Ping & Diagnostics | 30/30 | Gets "LAN," "tools," "ping," "diagnostics" indexed. |
| C | Device Discovery & Diagnostics | 30/30 | Highlights the unique scanning feature but misses tool-name keywords. |

**My recommendation is Option A.** It reads naturally, hits exact tool-name searches people actually type, and doesn't duplicate any word from the recommended title.

### Recommended Keywords Field

Your suggested keywords are strong. Here's an optimized 100-character keyword string that avoids duplicating anything from the recommended Title A + Subtitle A:

```
wlan,netscan,port,bonjour,tcp,latency,lan,dns,heatmap,whois,device,monitor,diagnostic,ip,network
```

**Character count: 96/100**

Words already indexed via Title + Subtitle (DO NOT repeat): wifi, scanner, map, ping, traceroute, speed, test, netmonitor

**Keyword reasoning:**

| Keyword | Why |
|---------|-----|
| wlan | Common European search term for WiFi networks |
| netscan | Compound search term used by power users |
| port | "port scanner" combines with "scanner" from title |
| bonjour | Unique feature, technical users search for this |
| tcp | Protocol name, technical searches |
| latency | Key metric people search when diagnosing network issues |
| lan | "lan scanner" combines with "scanner" from title |
| dns | "dns lookup" is a common search |
| heatmap | Unique differentiator feature, searchable |
| whois | Tool name people search directly |
| device | "device scanner/discovery" combinations |
| monitor | "network monitor" combines with "network" if in keywords |
| diagnostic | Covers "network diagnostic" searches |
| ip | "ip scanner" combines with "scanner" from title |
| network | Critical base keyword for combinations |

> **Note:** Apple combines words across all three fields. So "lan" in keywords + "scanner" in the title = you rank for "lan scanner" without needing the full phrase.

---

## NetMonitor Pro (macOS) — $9.99

### Current Metadata

| Field | Current | Chars |
|-------|---------|-------|
| Title | NetMonitor Pro | 14/30 |
| Subtitle | Network Monitor & Diagnostics | 29/30 |
| Keywords | *(unknown)* | ?/100 |

### Problems with Current Metadata

**Title** — You're leaving 16 characters unused. That's a huge missed opportunity. "Pro" conveys quality but doesn't help with search.

**Subtitle** — "Network Monitor" repeats "Monitor" which is already in your app name "NetMonitor." Apple will only count it once, so you're burning subtitle characters on a duplicate concept. "Diagnostics" is good.

### Recommended Title Options

| Option | Title | Chars | Rationale |
|--------|-------|-------|-----------|
| **A (Recommended)** | NetMonitor Pro: Network Scanner | 31 ❌ → **NetMonitor Pro: Net Scanner** | 28/30 | Adds "scanner" — the #1 keyword in this category. "Net" creates combinations. |
| B | NetMonitor Pro — LAN Scanner | 28/30 | Direct, clear. "LAN Scanner" is a high-intent macOS search. |
| C | NetMonitor Pro: WiFi Analyzer | 29/30 | Targets a different keyword cluster. "Analyzer" is strong on Mac. |

**Honestly, let me give you a better option:**

| **D (My actual pick)** | NetMonitor Pro: WiFi & LAN Scan | 31 ❌ |

One char over. Let's trim:

| **D (Revised)** | NetMonitor Pro: WiFi & LAN Map | 30/30 |

This gets "wifi," "lan," and "map" indexed alongside your brand. "Map" is unique to your GeoTrace/network map feature and differentiates from competitors.

**Alternative D2:** `NetMonitor Pro – WiFi Scanner` (29/30) — simpler, hits the top keyword.

### Recommended Subtitle Options

| Option | Subtitle | Chars | Rationale |
|--------|----------|-------|-----------|
| **A (Recommended)** | Ping, Traceroute & Port Scanner | 31 ❌ → **Ping, Traceroute & Port Scan** | 29/30 | Three high-value tool keywords not in title. |
| B | Speed Test & Network Diagnostic | 31 ❌ → **Speed Test & Net Diagnostics** | 29/30 | Different keyword cluster. |
| C | Device Discovery & Diagnostics | 30/30 | Feature-focused but misses tool-name keywords. |

**My recommendation:** Go with **Subtitle A** if you use Title D (WiFi & LAN Map), since it doesn't duplicate anything. You'd have: wifi, lan, map, ping, traceroute, port, scan all indexed between title and subtitle.

### Recommended Keywords Field

Using Title D + Subtitle A, here's the optimized keyword string:

```
wlan,netscan,bonjour,tcp,latency,dns,whois,speed,test,monitor,diagnostic,device,network,ip,heatmap
```

**Character count: 100/100** ✅

Words already indexed via Title + Subtitle (DO NOT repeat): netmonitor, pro, wifi, lan, map, ping, traceroute, port, scan

---

## Side-by-Side Final Recommendations

### NetMonitor Mobile (iOS)

| Field | Current | Recommended |
|-------|---------|-------------|
| **Title** | NetMonitor Mobile | **NetMonitor: WiFi Scanner & Map** |
| **Subtitle** | Pro Network Tools. No Cloud. | **Ping, Traceroute & Speed Test** |
| **Keywords** | *(unknown)* | `wlan,netscan,port,bonjour,tcp,latency,lan,dns,heatmap,whois,device,monitor,diagnostic,ip,network` |

**Unique indexed words: ~27** (up from ~7-8 estimated currently)

### NetMonitor Pro (macOS)

| Field | Current | Recommended |
|-------|---------|-------------|
| **Title** | NetMonitor Pro | **NetMonitor Pro: WiFi & LAN Map** |
| **Subtitle** | Network Monitor & Diagnostics | **Ping, Traceroute & Port Scan** |
| **Keywords** | *(unknown)* | `wlan,netscan,bonjour,tcp,latency,dns,whois,speed,test,monitor,diagnostic,device,network,ip,heatmap` |

**Unique indexed words: ~27** (up from ~8-9 estimated currently)

---

## Description Optimization (Conversion-Focused)

The description isn't indexed, but it IS what converts browsers into buyers. A few suggestions based on your current descriptions:

### Open with the hook and social proof line

Your current opening is good but could hit harder. Consider:

> **Current:** "Professional network diagnostics in your pocket. 10 tools, visual traceroute, device discovery, real-time health scoring — no ads, no cloud, no subscription."

> **Suggested:** "10 professional network tools. Zero cloud. Zero ads. Zero subscriptions. See every device on your network, trace routes across the globe, and diagnose issues in seconds — all processed locally on your device."

The key change: lead with the concrete number (10 tools), make the privacy message punchier with the "Zero" repetition, and immediately paint a picture of what the app does.

### Add a "Who It's For" section higher up

Your current description buries this at the bottom. Move it up and make it scannable:

> **Network admins** — Monitor infrastructure and catch rogue devices.
> **Developers** — Debug connectivity, inspect DNS, scan ports.
> **Homelab enthusiasts** — Map your network and track every device.
> **Privacy-conscious users** — Everything runs locally. Period.

### Shorten the tool descriptions

Users skim. Your current bullet points are thorough but verbose. For the App Store listing, consider trimming each tool to one punchy line instead of the explanatory format.

---

## Additional ASO Recommendations

### Screenshots & Preview Video
Screenshots are the #1 conversion factor after the icon. A few thoughts:

- **First screenshot** should show the Dashboard with the health score front and center — it's visually impressive and immediately communicates "this app is serious"
- **GeoTrace map screenshot** is your differentiator — make it screenshot #2 or #3
- Consider a short **App Preview video** (15-30s) showing a live scan discovering devices, then a GeoTrace animation. Video previews auto-play in search results and dramatically increase tap-through rates

### Ratings Strategy
NetMonitor Mobile has 5 ratings (5.0 stars) — that's great quality but low volume. NetMonitor Pro has essentially none. Consider:

- Implement `SKStoreReviewController` if you haven't already — Apple allows 3 prompts per 365-day period
- Trigger it after a successful scan completion (positive moment) rather than on launch
- Even getting to 15-20 ratings makes a meaningful difference in the Utilities category

### Localization (Low-Hanging Fruit)
You can add localized keywords for other English-speaking locales (UK, Australia, Canada) without translating the app. Each locale gets its own 100-character keyword field. At minimum, add UK English metadata — Apple indexes it separately and it's free real estate.

### Category
You're in **Utilities** which is correct, but consider whether **Developer Tools** as a secondary category might help for the Pro version on Mac. Power users browsing that category are your exact target audience.

### Update Cadence
Apps that update metadata every 4-6 weeks consistently outrank static listings. Even if you're not shipping new features, refreshing keywords based on what's trending can improve rankings.

---

## Keyword Coverage Comparison

Here's how your suggested keyword list maps to the final recommendations:

| Your Suggested Keyword | Where It Lands |
|------------------------|---------------|
| wlan | ✅ Keywords field (both apps) |
| network | ✅ Keywords field (both apps) |
| scanner / scan | ✅ Title (Mobile), Subtitle (Pro) |
| map | ✅ Title (both apps) |
| ping | ✅ Subtitle (both apps) |
| traceroute | ✅ Subtitle (both apps) |
| wifi | ✅ Title (both apps) |
| speed | ✅ Subtitle (Mobile), Keywords (Pro) |
| test | ✅ Subtitle (Mobile), Keywords (Pro) |
| dns | ✅ Keywords field (both apps) |
| port | ✅ Keywords (Mobile), Subtitle (Pro) |
| bonjour | ✅ Keywords field (both apps) |
| tcp | ✅ Keywords field (both apps) |
| latency | ✅ Keywords field (both apps) |
| lan | ✅ Keywords (Mobile), Title (Pro) |
| netscan | ✅ Keywords field (both apps) |

**All 16 of your suggested keywords are covered.** Plus we added: heatmap, whois, device, monitor, diagnostic, ip — 6 additional high-value terms.
