#!/bin/bash
# fetch_bridges.sh — discovers working obfs4 bridges from a git repository.
#
# Algorithm:
#   1. git pull (or clone on first run)
#   2. Extract all bridges from all source files, sorted newest-first
#      (uses git blame to determine when each line was added)
#   3. Test bridges in that order, stopping early once NEED is reached
#
# Usage: fetch_bridges.sh [count]
#   count — minimum number of working bridges needed (default: MIN_BRIDGES from config.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

NEED="${1:-$MIN_BRIDGES}"

log "=== fetch_bridges.sh started (need at least $NEED) ==="

# --- Step 1: clone or update the repository ---
ensure_repo() {
    if [ -d "$REPO_DIR/.git" ]; then
        local before after
        before=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo "")
        log "Updating existing repo..."
        if git -C "$REPO_DIR" pull --ff-only >> "$LOG_FILE" 2>&1; then
            after=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo "")
            if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
                log "Repo updated: $before → $after"
            else
                log "Repo already up to date"
            fi
        else
            log "WARNING: git pull failed, using existing local copy"
        fi
    else
        log "Cloning repo $REPO_URL ..."
        mkdir -p "$(dirname "$REPO_DIR")"
        if ! git clone "$REPO_URL" "$REPO_DIR" >> "$LOG_FILE" 2>&1; then
            log "ERROR: git clone failed"
            exit 1
        fi
    fi
}

# --- Step 2: extract all bridges sorted newest-first ---
# git blame provides author-time (Unix timestamp) for each line.
# Sort by timestamp descending — freshest bridges first.
get_bridges_newest_first() {
    local all=""

    for src in "${BRIDGES_SOURCES[@]}"; do
        local file="$REPO_DIR/$src"
        [ -f "$file" ] || continue

        log "Indexing $src ..."

        local bridges
        bridges=$(git -C "$REPO_DIR" blame --line-porcelain "$file" 2>/dev/null \
            | awk '
                /^author-time / { ts = $2 }
                /^\t/          { if (ts && $0 ~ /obfs4/) print ts "\t" substr($0, 2) }
            ' \
            | sort -rn \
            | cut -f2-)

        if [ -n "$bridges" ]; then
            count=$(echo "$bridges" | grep -c . || true)
            log "  → $count bridge(s) indexed from $src"
            all=$( (echo "$all"; echo "$bridges") | grep . || true)
        fi
    done

    echo "$all"
}

# --- Main ---
ensure_repo

log "Building bridge list sorted newest-first from git blame..."
all_bridges=$(get_bridges_newest_first || echo "")

if [ -z "$all_bridges" ]; then
    log "ERROR: No obfs4 bridges found in any source file"
    exit 1
fi

total=$(echo "$all_bridges" | grep -c . || true)
log "Total bridges indexed: $total"

log "Testing bridges (newest first, stop at $NEED working)..."
result=$(echo "$all_bridges" | check_bridges_batch "$NEED" || echo "")

count=$(echo "$result" | grep -c . || true)
log "Working bridges found: $count"
echo "$result"
exit 0
