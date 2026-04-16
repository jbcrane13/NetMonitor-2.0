# iOS Wi-Fi Shortcut Setup Guide

**NetMonitor 2.0 — Wi-Fi Heatmap companion Shortcut**

---

## Why a Shortcut?

Apple does not give third-party apps direct access to Wi-Fi signal strength (RSSI) on iOS. The `NEHotspotNetwork` API returns 0.0 for signal strength for apps that are not registered hotspot helpers. Apple's "Get Network Details" Shortcuts action is the only approved way to read real dBm values from the Wi-Fi chipset on iOS 17 and later.

The companion Shortcut acts as a thin bridge: NetMonitor asks Shortcuts to run, Shortcuts reads the chipset data, and then calls back into NetMonitor's built-in `Save Wi-Fi Reading to NetMonitor` action with the result. The entire round-trip takes about 1.5–2.5 seconds.

---

## Prerequisites

- iPhone or iPad running **iOS 18 or later**
- **NetMonitor** installed and opened at least once (this registers the built-in action with Shortcuts)
- The **Shortcuts** app (pre-installed on all modern iPhones)

---

## Build the Shortcut (2 actions)

![Step 1: Get Network Details action](images/shortcut-step1.png)

### Step 1 — Add "Get Network Details"

1. Open the **Shortcuts** app.
2. Tap **+** in the top-right corner to create a new shortcut.
3. Tap **Add Action** and search for **Get Network Details**.
4. Tap the result to add it.
5. In the action tile, tap the blue pill that says **"My Details"** and change it to **"Wi-Fi Details"**.

### Step 2 — Add "Save Wi-Fi Reading to NetMonitor"

![Step 2: Save Wi-Fi Reading action](images/shortcut-step2.png)

1. Below the first action, tap **Add Action**.
2. Search for **Save Wi-Fi Reading** — it appears under the **NetMonitor** section.
3. Tap it to add it.
4. Map each parameter to the matching output from step 1:

| Parameter in NetMonitor action | Value from "Get Network Details" |
|-------------------------------|----------------------------------|
| Network Name (SSID) | Network Name |
| BSSID | BSSID |
| Signal Strength (RSSI, dBm) | Signal Strength |
| Noise (dBm) | Noise |
| Channel | Channel |
| TX Rate (Mbps) | TX Rate |
| RX Rate (Mbps) | RX Rate |
| Wi-Fi Standard | Wi-Fi Standard |

> **Note:** Noise, TX Rate, RX Rate, and Wi-Fi Standard are optional. If "Get Network Details" does not return them on your device, leave those parameters unmapped — NetMonitor handles missing values gracefully.

### Step 3 — Name the shortcut

Tap the shortcut name at the top of the screen (defaults to something like "New Shortcut") and rename it to exactly:

**Wi-Fi to NetMonitor**

> The name must match exactly — it is case-sensitive and requires a single space on each side of the word "to". NetMonitor triggers the shortcut by name.

Tap **Done** to save.

---

## Verify it works

1. Open **NetMonitor** → **Heatmap**.
2. Tap **Test Connection** on the Wi-Fi Setup screen.
3. Shortcuts will open briefly, run the shortcut, and return to NetMonitor.
4. If the test succeeds you will see your network name, RSSI value, and channel displayed. Tap **Start Surveying**.

---

## Troubleshooting

### "Save Wi-Fi Reading to NetMonitor" action is not visible in Shortcuts

The action is registered by the app when it launches. Try:
1. Force-quit NetMonitor (swipe up from the app switcher).
2. Relaunch NetMonitor and wait for it to fully load.
3. Return to Shortcuts and search again.
4. Ensure your device is running **iOS 18 or later** — the App Intents registration API requires iOS 18+.

### Shortcut times out or NetMonitor shows "Connection Test Failed"

- Verify the shortcut name is exactly **Wi-Fi to NetMonitor** — check for extra spaces, wrong capitalisation, or smart-quote characters if you typed it manually.
- Open Shortcuts and run the shortcut manually by tapping the play button. If it errors, check the field mappings in step 2.
- Make sure you are connected to a Wi-Fi network (not cellular only) when running the shortcut.

### RSSI shows 0 or is missing

- Verify the **Signal Strength** parameter in the "Save Wi-Fi Reading to NetMonitor" action is bound to the **Signal Strength** value from "Get Network Details", not to the full dictionary output.
- Tap the Signal Strength parameter tile and confirm it shows a Shortcuts variable (the blue pill), not a typed number.

### "Get Network Details" action is not in Shortcuts

This action requires **iOS 17 or later**. Update your device if the action does not appear.

---

## Frequently asked questions

**Does this shortcut run in the background?**
No. iOS requires Shortcuts automations with timers to prompt the user each time. The shortcut runs in the foreground — you will see Shortcuts briefly open and close during each heatmap measurement. This is expected and typically takes under a second.

**Do I need an iCloud account to install the shortcut?**
No. You build the shortcut manually in the Shortcuts app using actions that are already on your device. No download or iCloud link is required.

**Will this work on iPad?**
Yes, on any iPad running iPadOS 18 or later with a Wi-Fi connection.
