#!/usr/bin/env bash
set -euo pipefail

# Optional network egress firewall initialization (requires --cap-add=NET_ADMIN --cap-add=NET_RAW)
if [[ "${ENABLE_FIREWALL:-0}" == "1" || "${ENABLE_FIREWALL:-false}" == "true" ]]; then
    if [[ "$(id -u)" == "0" ]]; then
        /usr/local/bin/init_firewall.sh
    else
        echo "WARNING: ENABLE_FIREWALL=1 requires starting container as root or with sudo privileges." >&2
    fi
fi

mkdir -p "${CODEX_HOME:-/home/codex/.codex}"

# If explicit binary or subcommand is passed, dispatch appropriately
if [[ $# -gt 0 ]]; then
    case "$1" in
        codex|codex-exec|codex-app-server|exec-server|apply_patch|bwrap|codex-linux-sandbox|bash|sh)
            exec "$@"
            ;;
        exec|app-server|exec-server|execpolicy|responses-api-proxy)
            exec /usr/local/bin/codex "$@"
            ;;
    esac
fi

# Dispatch based on HARNESS_MODE environment variable (defaults to `exec`)
case "${HARNESS_MODE:-exec}" in
    app-server)
        LISTEN_URL="${HARNESS_LISTEN_URL:-ws://0.0.0.0:8080}"
        exec /usr/local/bin/codex-app-server --listen "${LISTEN_URL}" "$@"
        ;;
    exec-server)
        LISTEN_URL="${EXEC_SERVER_LISTEN_URL:-ws://0.0.0.0:31987}"
        exec /usr/local/bin/exec-server --listen "${LISTEN_URL}" "$@"
        ;;
    exec|*)
        exec /usr/local/bin/codex-exec "$@"
        ;;
esac
