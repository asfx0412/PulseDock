#!/bin/zsh
# Authenticate GitHub CLI through the current Clash Verge HTTP/mixed port.
# Keep this outside PulseDock.app: it only changes this child process's
# environment and never stores a token in the repository.
set -euo pipefail

PROXY_URL="${PULSEDOCK_GITHUB_PROXY:-http://127.0.0.1:7897}"
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"

command -v gh >/dev/null || { print "GitHub CLI (gh) is not installed." >&2; exit 1; }
print "Using GitHub proxy: $PROXY_URL"
print "Clash Verge must be running with this HTTP/mixed port enabled."
gh auth logout -h github.com -u asfx0412 >/dev/null 2>&1 || true
exec gh auth login -h github.com --git-protocol https --web
