# iOS Wi-Fi Shortcut Setup Guide

**NetMonitor 2.0 — Wi-Fi Heatmap companion Shortcut**

---

## Why a Shortcut?

Apple does not give third-party apps direct access to Wi-Fi signal strength (RSSI) on iOS. The `NEHotspotNetwork` API returns 0.0 for signal strength for apps that are not registered hotspot helpers. Apple's "Get Network Details" Shortcuts action is the only approved way to read real dBm values from the Wi-Fi chipset on iOS 17 and later.

The companion Shortcut acts as a thin bridge: NetMonitor asks Shortcuts to run, Shortcuts reads each chipset field in turn, then calls NetMonitor's built-in `Save Wi-Fi Reading to NetMonitor` action with the full payload. The entire round-trip takes roughly 2–3 seconds depending on how many fields you capture.

---

## Prerequisites

- iPhone or iPad running **iOS 18 or later**
- **NetMonitor** installed and opened at least once (this registers the built-in action with Shortcuts)
- The **Shortcuts** app (pre-installed on all modern iPhones)

---

## Quickest path: one-tap install

NetMonitor publishes the companion Shortcut to iCloud. From inside the app:

1. Open NetMonitor → **Heatmap** → **Wi-Fi Setup**.
2. Tap **Install Wi-Fi Shortcut**.
3. The Shortcuts app opens with "Wi-Fi to NetMonitor" preconfigured. Review the 9 actions and tap **Add Shortcut**.
4. Return to NetMonitor and tap **Test Connection** to confirm.

You can also open the install link directly on your device:

<https://www.icloud.com/shortcuts/ae1acdf1630e4d1daf998402d5ddc4c0>

If the install link is blocked on your network or the Shortcut ever needs troubleshooting, follow the manual steps below.

---

## Build the Shortcut (manual fallback)

The companion shortcut needs **one "Get Network Details" action per field you want to capture**, followed by a single "Save Wi-Fi Reading to NetMonitor" action that collects them all. A full-data shortcut has 9 actions; a minimum shortcut (SSID + RSSI + Channel only) has 4.

![Step 1: Get Network Details action](images/shortcut-step1.png)

### Step 1 — Add one "Get Network Details" action per field

Apple's "Get Network Details" action returns only one value per invocation (you pick the field from a dropdown). Add a separate action for each piece of data you want:

1. Open the **Shortcuts** app.
2. Tap **+** in the top-right to create a new shortcut.
3. Tap **Add Action** and search for **Get Network Details**.
4. Tap the result to add it. It defaults to "Get Wi-Fi network's Network Name".
5. Rename its output variable so it is easy to reference later (tap the blue variable name → Rename → `SSID`).
6. **Repeat** for each additional field you want. Tap the existing action's detail dropdown to pick a different field, or duplicate and change the selection. Rename each output variable to match the field:

| Field to capture | Rename variable to |
|------------------|--------------------|
| **Network Name** (required)    | `SSID` |
| **RSSI** (required)            | `RSSI` |
| **Channel Number** (required)  | `Channel` |
| BSSID (optional)               | `BSSID` |
| Noise (optional, improves heatmap quality) | `Noise` |
| TX Rate (optional)             | `TXRate` |
| RX Rate (optional)             | `RXRate` |
| Wi-Fi Standard (optional)      | `WiFiStandard` |

> **Tip:** Noise is especially valuable — NetMonitor uses it to compute SNR, which improves heatmap accuracy. Include it if your device exposes it.

### Step 2 — Add "Save Wi-Fi Reading to NetMonitor"

![Step 2: Save Wi-Fi Reading action](images/shortcut-step2.png)

1. Below the Get Network Details actions, tap **Add Action**.
2. Search for **Save Wi-Fi Reading** — it appears under the **NetMonitor** section.
3. Tap it to add it.
4. Map each parameter to the matching variable from step 1:

| Parameter in NetMonitor action | Variable from step 1 |
|-------------------------------|----------------------|
| Network Name (SSID) | `SSID` |
| Signal Strength (RSSI, dBm) | `RSSI` |
| Channel | `Channel` |
| BSSID | `BSSID` |
| Noise (dBm) | `Noise` |
| TX Rate (Mbps) | `TXRate` |
| RX Rate (Mbps) | `RXRate` |
| Wi-Fi Standard | `WiFiStandard` |

> **Note:** Leave any optional parameters unmapped if you didn't capture them in step 1 — NetMonitor handles missing values gracefully.

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

- Verify your "Get Network Details" action for RSSI is set to return **RSSI** in its dropdown (not Network Name or another field).
- In "Save Wi-Fi Reading to NetMonitor", confirm the Signal Strength parameter shows a Shortcuts variable (blue pill) pointing at your renamed `RSSI` variable — not a typed number.

### "Get Network Details" action is not in Shortcuts

This action requires **iOS 17 or later**. Update your device if the action does not appear.

---

## Frequently asked questions

**Does this shortcut run in the background?**
No. iOS requires Shortcuts automations with timers to prompt the user each time. The shortcut runs in the foreground — you will see Shortcuts briefly open and close during each heatmap measurement. This is expected and typically takes under a second.

**Do I need an iCloud account to install the shortcut?**
No. The one-tap install fetches the template from Apple's public iCloud share URL — you can tap **Add Shortcut** without being signed in to iCloud. If you prefer zero network traffic you can always follow the manual build steps above.

**Will this work on iPad?**
Yes, on any iPad running iPadOS 18 or later with a Wi-Fi connection.
