#!/bin/bash
# health_check.sh — checks Tor connectivity via torsocks.
# Called by cron every 5 minutes.
# Exit 0 — Tor is reachable.
# Exit 1 — Tor is down (rotate_bridges.sh should run).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# If rotate_bridges.sh is already running, don't interfere
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log "Rotation already in progress, skipping health check"
    exit 0
fi
flock -u 200

# Ensure torsocks is installed
if ! command -v torsocks &>/dev/null; then
    log "ERROR: torsocks not found. Install: apt install torsocks"
    exit 1
fi

log "Health check starting..."

for attempt in $(seq 1 $((HEALTH_RETRIES + 1))); do
    log "Attempt $attempt..."

    if torsocks curl --max-time "$HEALTH_TIMEOUT" --silent --fail "$HEALTH_URL" >/dev/null 2>&1; then
        log "OK — Tor connection is working"
        exit 0
    fi

    if [ "$attempt" -le "$HEALTH_RETRIES" ]; then
        log "Attempt $attempt failed, waiting ${HEALTH_RETRY_DELAY}s before retry..."
        sleep "$HEALTH_RETRY_DELAY"
    fi
done

log "FAILED — All $((HEALTH_RETRIES + 1)) attempts failed. Tor connection is down."
exit 1
