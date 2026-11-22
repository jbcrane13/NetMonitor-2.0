# NetMonitor

Network monitoring for macOS and iOS: find the devices on a local network, say what each one is, and watch them over time.

## Device identity

**Device**:
One piece of hardware on a network, as NetMonitor knows it across scans. Saved once per network.
_Avoid_: host, node, client

**Device identity**:
What a device is: its maker, model and friendly name.
_Avoid_: device info, metadata

**Identity source**:
The way an identity value was learned (Bonjour TXT record, UniFi discovery reply, UPnP description, MAC prefix, hostname guess). Sources are ranked; a higher-ranked value is never replaced by a lower-ranked one.
_Avoid_: provider, origin

**Maker**:
The company that makes the device, as shown to the user. The highest-ranked of the device's own announcement, the MAC-prefix maker and a hostname guess.
_Avoid_: manufacturer, vendor (when the resolved value is meant)

**MAC-prefix maker**:
The company registered for the first three octets of a MAC address. Often the network-chip maker rather than the brand on the device, and missing for private MACs.
_Avoid_: OUI vendor (in UI copy), vendor (when the resolved maker is meant)

**Model**:
The device's product model, such as `MacBookPro18,1` or "UniFi Pro Max 16 Switch".
_Avoid_: model name, product

**Friendly name**:
A name the device announces for itself (UPnP friendly name, UniFi device name).
_Avoid_: display name (when this specific source is meant)

**Hostname**:
The name reverse DNS returns for the device's IP. Not an identity source of its own, but the input to a hostname guess.
_Avoid_: name (unqualified)

**Custom name**:
A name the user gave the device. Always shown when set; never ranked against identity sources.
_Avoid_: nickname, alias

**Device name**:
The name shown for a device: its custom name, else its friendly name, else its hostname, else its IP address.
_Avoid_: display name, title

**Hostname guess**:
A maker and model inferred from a hostname such as `unifi-pro-max-16-switch`. The lowest-ranked identity source.

## Matching

**Device match**:
Deciding which saved device an observation from a scan belongs to, by MAC address, IP and name.
_Avoid_: dedupe, reconcile

**Placeholder MAC**:
A MAC address that carries no identity (`00:00:00:00:00:00`, iOS's `02:00:00:00:00:00`). Treated as no MAC.

**Private MAC**:
A randomized MAC address (locally administered bit set) that a phone or laptop may rotate. A new private MAC is the same device only when the IP and a non-empty name both match exactly one saved device.
_Avoid_: random MAC, rotating MAC
