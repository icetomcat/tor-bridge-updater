# Tor Bridge Updater

Automated obfs4 bridge health checking, rotation, and Tor configuration updater.
Designed for low-resource VPS with intermittent connectivity to a primary proxy.

## Architecture

```
cron (*/5 min) → health_check.sh
                    │
              torsocks curl (retry ×2)
                    │
              OK? ──YES──→ exit 0
                    │
                   NO
                    │
              rotate_bridges.sh (flock mutex)
                    │
          ┌─ re-test ALL current torrc bridges
          ├─ < MIN_BRIDGES? → fetch_bridges.sh
          │     ├─ git pull from Tor-Bridges-Collector
          │     ├─ sort bridges newest-first (git blame)
          │     └─ test with early stop at MIN_BRIDGES
          └─ shuf | head → /etc/tor/torrc → restart tor
```

## Files

| File | Purpose |
|------|---------|
| `config.sh` | Shared settings, `check_bridge()`, `check_bridges_batch()`, logging |
| `health_check.sh` | Tests Tor connectivity via `torsocks curl` with retries |
| `fetch_bridges.sh` | Clones/pulls bridge repo, tests bridges newest-first |
| `rotate_bridges.sh` | Orchestrator: re-test existing, fetch new, update torrc, restart tor |

## Requirements

- `tor`, `torsocks`, `git`, `curl`, `flock`, `shuf` (coreutils)
- Root access (for `/etc/tor/torrc` writes and `systemctl restart tor`)
- Bridge source: [scriptzteam/Tor-Bridges-Collector](https://github.com/scriptzteam/Tor-Bridges-Collector)

## Deployment

```bash
# Copy scripts to server
scp *.sh root@server:/usr/local/bin/
ssh root@server chmod +x /usr/local/bin/{config,health_check,fetch_bridges,rotate_bridges}.sh

# Install cron job (runs every 5 minutes)
ssh root@server 'echo "*/5 * * * * root /usr/local/bin/health_check.sh || /usr/local/bin/rotate_bridges.sh" > /etc/cron.d/tor-bridges'
```

## Manual usage

```bash
rotate_bridges.sh --dry-run    # preview changes without applying
rotate_bridges.sh --force      # skip lock (manual run)
fetch_bridges.sh               # find working bridges (stdout)
```

## Configuration

Edit `config.sh` to adjust:

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_JOBS` | `4` | Parallel bridge checks |
| `TIMEOUT` | `30` | Seconds per bridge check |
| `MIN_BRIDGES` | `4` | Target bridge count in torrc |
| `HEALTH_URL` | `https://check.torproject.org/api/ip` | Health check endpoint |
| `BRIDGES_SOURCES` | `bridges-obfs4`, `bridges-obfs4-guards`, `bridges-obfs4-archive` | Source files in repo |
