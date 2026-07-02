#!/bin/bash
# rotate_bridges.sh — main orchestrator for Tor bridge rotation.
#
# Algorithm:
#   1. Re-test ALL current bridges from /etc/tor/torrc
#   2. If working bridges < MIN_BRIDGES → call fetch_bridges.sh for more
#   3. If still 0 working bridges → ALERT, exit 1
#   4. Shuffle working bridges, pick up to MIN_BRIDGES → update torrc
#   5. systemctl reload/restart tor
#
# Usage:
#   rotate_bridges.sh            — normal run (requires lock)
#   rotate_bridges.sh --force    — skip lock check (manual run)
#   rotate_bridges.sh --dry-run  — preview changes without applying

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

FORCE=false
DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --force) FORCE=true ;;
        --dry-run) DRY_RUN=true ;;
        *) log "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# --- Lock (prevents concurrent runs) ---
if [ "$FORCE" != "true" ]; then
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log "Another rotate_bridges.sh instance is already running. Exiting."
        exit 0
    fi
fi

log "=== rotate_bridges.sh started ==="

# --- Step 1: extract current bridges from torrc ---
if [ ! -f "$TORRC_FILE" ]; then
    log "FATAL: $TORRC_FILE not found!"
    exit 1
fi

current_bridges=$(grep -E '^Bridge\s+obfs4' "$TORRC_FILE" | sed 's/^Bridge\s\+//' || true)

if [ -z "$current_bridges" ]; then
    log "WARNING: No obfs4 bridges in $TORRC_FILE"
else
    log "Found $(echo "$current_bridges" | wc -l) bridge(s) in torrc"
fi

# --- Step 2: re-test current bridges ---
candidates=""
if [ -n "$current_bridges" ]; then
    log "--- Re-testing current torrc bridges ---"
    candidates=$(echo "$current_bridges" | check_bridges_batch || echo "")
fi

cand_count=$(echo "$candidates" | grep -c . || echo 0)
log "Working bridges from current torrc: $cand_count"

# --- Step 3: if not enough, fetch more from the repository ---
if [ "$cand_count" -lt "$MIN_BRIDGES" ]; then
    log "Need at least $MIN_BRIDGES bridges, have $cand_count. Fetching more..."

    new_bridges=$(bash "$SCRIPT_DIR/fetch_bridges.sh" "$MIN_BRIDGES" || echo "")

    if [ -n "$new_bridges" ]; then
        # Merge and deduplicate
        candidates=$( (echo "$candidates"; echo "$new_bridges") | grep . | sort -u || true)
        cand_count=$(echo "$candidates" | grep -c . || echo 0)
        log "After fetch: $cand_count unique working bridge(s)"
    fi
fi

# --- Step 4: check result ---
if [ "$cand_count" -eq 0 ]; then
    log "ALERT: Zero working bridges found! Nothing to deploy."
    log "ALERT: Check tor connectivity manually and update bridge sources."
    exit 1
fi

# Pick random MIN_BRIDGES (or however many we have)
if [ "$cand_count" -le "$MIN_BRIDGES" ]; then
    selected="$candidates"
    log "Using all $cand_count working bridge(s) (≤ $MIN_BRIDGES)"
else
    selected=$(echo "$candidates" | shuf -n "$MIN_BRIDGES")
    log "Selected $MIN_BRIDGES random bridge(s) from $cand_count candidates"
fi

# --- Step 5: update torrc ---
new_torrc="$TORRC_FILE.new"
# Keep all lines except existing Bridge obfs4 entries
grep -v '^Bridge\s\+obfs4' "$TORRC_FILE" > "$new_torrc"

# Append selected bridges
while IFS= read -r bridge; do
    [ -n "$bridge" ] && echo "Bridge $bridge"
done <<< "$selected" >> "$new_torrc"

if [ "$DRY_RUN" = "true" ]; then
    log "DRY RUN — new torrc would be:"
    cat "$new_torrc"
    rm -f "$new_torrc"
    log "DRY RUN — done. No changes applied."
    exit 0
fi

# Atomic replacement
mv "$new_torrc" "$TORRC_FILE"
log "Updated $TORRC_FILE with $cand_count bridge(s)"

# --- Step 6: restart tor ---
if systemctl is-active --quiet tor 2>/dev/null; then
    log "Reloading tor..."
    if systemctl reload tor 2>/dev/null || systemctl restart tor; then
        log "Tor service restarted successfully"
    else
        log "ERROR: Failed to restart tor"
        exit 1
    fi
else
    log "Starting tor..."
    systemctl start tor || log "WARNING: Failed to start tor"
fi

log "=== rotate_bridges.sh completed ==="
exit 0
