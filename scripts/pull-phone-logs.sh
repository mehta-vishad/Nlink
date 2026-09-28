#!/bin/bash
#
# Copies the app's HTTP log mirror off a connected iPhone into .phone-logs/
# (gitignored) and prints a summary.
#
# Only Library/Logs/http-*.jsonl is copied — logs BetterBlueKit has already
# redacted (no password, PIN, tokens, GPS, or full VIN). The SwiftData store is
# never copied: it also holds the Bluelink password and PIN in plain text.
#
#     ./scripts/pull-phone-logs.sh              last 30 requests
#     ./scripts/pull-phone-logs.sh --last 100   last 100 requests
#     ./scripts/pull-phone-logs.sh --all        every request
#     DEVICE=<udid> ./scripts/pull-phone-logs.sh   pick a specific iPhone
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.phone-logs"
LAST=30

while [ $# -gt 0 ]; do
    case "$1" in
        --all)  LAST=0; shift ;;
        --last) LAST="$2"; shift 2 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

GROUP="$(awk -F' *= *' '/^BB_APP_GROUP/ { print $2 }' "$ROOT/Config/Local.xcconfig" 2>/dev/null || true)"
if [ -z "$GROUP" ]; then
    echo "No BB_APP_GROUP in Config/Local.xcconfig — run ./scripts/setup-signing.sh first." >&2
    exit 1
fi

if [ -z "${DEVICE:-}" ]; then
    DEVICES_JSON="$(mktemp)"
    trap 'rm -f "$DEVICES_JSON"' EXIT
    xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null 2>&1 || true
    DEVICE="$(python3 - "$DEVICES_JSON" <<'EOF'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    sys.exit(0)
phones = [
    d for d in devices
    if d.get("hardwareProperties", {}).get("reality") == "physical"
    and d.get("hardwareProperties", {}).get("platform") == "iOS"
    and d.get("connectionProperties", {}).get("pairingState") == "paired"
]
phones.sort(key=lambda d: d.get("connectionProperties", {}).get("tunnelState") != "connected")
if phones:
    print(phones[0]["hardwareProperties"]["udid"])
EOF
)"
fi

if [ -z "$DEVICE" ]; then
    echo "No paired iPhone found. Plug it in (or turn on Connect via network in Xcode) and unlock it." >&2
    exit 1
fi

mkdir -p "$OUT"
chmod 700 "$OUT"
rm -f "$OUT"/http-*.jsonl*

COPIED=0
for NAME in http-iphone.jsonl.1 http-iphone.jsonl http-widget.jsonl.1 http-widget.jsonl; do
    if xcrun devicectl device copy from \
        --device "$DEVICE" \
        --domain-type appGroupDataContainer \
        --domain-identifier "$GROUP" \
        --source "Library/Logs/$NAME" \
        --destination "$OUT/$NAME" >/dev/null 2>&1; then
        COPIED=$((COPIED + 1))
    else
        rm -f "$OUT/$NAME"
    fi
done

if [ "$COPIED" -eq 0 ]; then
    echo "Connected to the iPhone, but it has no HTTP logs yet."
    echo "Logs start once the app talks to a real account (Fake Vehicle Mode makes no requests)."
    exit 0
fi

python3 - "$OUT" "$LAST" <<'EOF'
import json, sys
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

out, last = Path(sys.argv[1]), int(sys.argv[2])
entries = []
for path in sorted(out.glob("http-*.jsonl*")):
    for raw in path.read_text().splitlines():
        try:
            entry = json.loads(raw)
        except json.JSONDecodeError:
            continue
        log = entry.get("log", {})
        when = datetime.fromisoformat(log.get("timestamp", "1970-01-01T00:00:00Z").replace("Z", "+00:00"))
        entries.append((when, entry.get("source", "?"), log))

entries.sort(key=lambda e: e[0])
shown = entries if last == 0 else entries[-last:]
by_source = {}
for _, source, _ in entries:
    by_source[source] = by_source.get(source, 0) + 1

print(f"{len(entries)} requests in .phone-logs/ ({', '.join(f'{n} {s}' for s, n in sorted(by_source.items()))})")
print(f"showing {len(shown)}, oldest first\n")
print(f"{'time':19}  {'from':7}  {'request':26}  {'status':>6}  {'secs':>6}  path")
for when, source, log in shown:
    status = log.get("responseStatus")
    status = "ERR" if log.get("error") else ("-" if status is None else str(status))
    path = urlparse(log.get("url", "")).path or log.get("url", "")
    print(f"{when.astimezone():%Y-%m-%d %H:%M:%S}  {source[:7]:7}  {str(log.get('requestType', '?'))[:26]:26}  "
          f"{status:>6}  {log.get('duration', 0):6.2f}  {path}")
EOF
