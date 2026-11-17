#!/usr/bin/env python3
"""Regenerate NetMonitorCore's offline maker (OUI) list from the IEEE MA-L registry (#384).

Run at release time, not at app runtime:

    python3 scripts/generate-oui-resource.py            # download from IEEE
    python3 scripts/generate-oui-resource.py oui.csv    # use a file already downloaded

Writes Packages/NetMonitorCore/Sources/NetMonitorCore/Resources/oui.tsv: one comment
line naming the source and date, then sorted "XXXXXX<TAB>Organization" lines. Rows whose
organisation is "Private" (confidential IEEE assignments) are dropped. Commit the output.
"""

import csv
import datetime
import io
import pathlib
import sys
import urllib.request

SOURCE_URL = "https://standards-oui.ieee.org/oui/oui.csv"
# IEEE's firewall rejects browser-like and default urllib agents; a plain curl agent works.
USER_AGENT = "curl/8.7.1"
MINIMUM_PREFIXES = 30_000
MAXIMUM_BYTES = 1_500_000
OUTPUT = (pathlib.Path(__file__).resolve().parent.parent
          / "Packages/NetMonitorCore/Sources/NetMonitorCore/Resources/oui.tsv")


def fetch() -> str:
    request = urllib.request.Request(SOURCE_URL, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        if response.status != 200:
            sys.exit(f"error: {SOURCE_URL} returned HTTP {response.status}")
        return response.read().decode("utf-8")


def main() -> None:
    text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8") if len(sys.argv) > 1 else fetch()
    rows = csv.reader(io.StringIO(text))
    header = next(rows, None)
    if header is None or header[:3] != ["Registry", "Assignment", "Organization Name"]:
        sys.exit(f"error: unexpected CSV header {header!r}")

    vendors: dict[str, str] = {}
    for row in rows:
        if len(row) < 3 or row[0] != "MA-L":
            continue
        prefix = row[1].strip().upper()
        name = " ".join(row[2].split())
        if len(prefix) != 6 or any(c not in "0123456789ABCDEF" for c in prefix):
            continue
        if not name or name.lower() == "private":
            continue
        vendors[prefix] = name

    if len(vendors) < MINIMUM_PREFIXES:
        sys.exit(f"error: only {len(vendors)} prefixes parsed (expected at least {MINIMUM_PREFIXES})")

    today = datetime.date.today().isoformat()
    lines = [f"# IEEE MA-L {SOURCE_URL} downloaded {today}, {len(vendors)} prefixes"]
    lines += [f"{prefix}\t{vendors[prefix]}" for prefix in sorted(vendors)]
    data = ("\n".join(lines) + "\n").encode("utf-8")
    if len(data) > MAXIMUM_BYTES:
        sys.exit(f"error: resource is {len(data)} bytes (limit {MAXIMUM_BYTES})")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(data)
    print(f"wrote {OUTPUT.relative_to(OUTPUT.parents[5])}: {len(vendors)} prefixes, {len(data)} bytes")


if __name__ == "__main__":
    main()
