#!/bin/bash
# User-configurable settings for the Tor bridge rotation system.
# Edit this file to match your environment and requirements.

# --- Paths ---
TORRC_FILE="/etc/tor/torrc"

# Bridge source repository
REPO_URL="https://github.com/scriptzteam/Tor-Bridges-Collector.git"

# Bridge source files inside the repo (checked in order)
BRIDGES_SOURCES=(
    "bridges-obfs4"         # main fresh bridges
    "bridges-obfs4-guards"  # guard bridges
    "bridges-obfs4-archive" # older bridges (last resort)
)

# --- Bridge testing ---
MAX_JOBS=4       # parallel tor instances for bridge checking
TIMEOUT=30       # seconds to wait for a bridge to connect
MIN_BRIDGES=4    # target number of bridges in torrc

# --- Health check ---
HEALTH_URL="https://check.torproject.org/api/ip"
HEALTH_RETRIES=2       # retry count after first failure
HEALTH_RETRY_DELAY=30  # seconds between retries
HEALTH_TIMEOUT=10      # curl timeout per attempt
