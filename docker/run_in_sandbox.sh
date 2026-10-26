#!/usr/bin/env bash
# Helper script to run the Codex Agent Harness inside a Docker Sandbox on a target workspace.
#
# Usage:
#   ./docker/run_in_sandbox.sh [--work-dir DIR] [--mode exec|app-server|exec-server] [--firewall] [HARNESS_ARGS...]
#
# Examples:
#   # 1. One-shot JSONL streaming execution on current directory:
#   ./docker/run_in_sandbox.sh -- --json --full-auto --skip-git-repo-check "Analyze repository structure"
#
#   # 2. Start bidirectional JSON-RPC App Server on port 8080:
#   ./docker/run_in_sandbox.sh --mode app-server
#
#   # 3. Start standalone Exec Server sandbox on port 31987:
#   ./docker/run_in_sandbox.sh --mode exec-server

set -euo pipefail

WORK_DIR="$(pwd)"
HARNESS_MODE="${HARNESS_MODE:-exec}"
ENABLE_FIREWALL="${ENABLE_FIREWALL:-0}"
IMAGE_NAME="${CODEX_HARNESS_IMAGE:-codex-harness:latest}"
PORT_MAPPING=()
CAP_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --work-dir)
      WORK_DIR="$(realpath "$2")"
      shift 2
      ;;
    --mode)
      HARNESS_MODE="$2"
      shift 2
      ;;
    --firewall)
      ENABLE_FIREWALL="1"
      CAP_ARGS+=(--cap-add=NET_ADMIN --cap-add=NET_RAW)
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

case "$HARNESS_MODE" in
  app-server)
    PORT_MAPPING+=(-p "${HARNESS_PORT:-8080}:8080")
    ;;
  exec-server)
    PORT_MAPPING+=(-p "${EXEC_SERVER_PORT:-31987}:31987")
    ;;
esac

exec docker run --rm -i \
  --security-opt seccomp=unconfined \
  "${CAP_ARGS[@]}" \
  "${PORT_MAPPING[@]}" \
  -e OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
  -e CODEX_API_KEY="${CODEX_API_KEY:-}" \
  -e HARNESS_MODE="${HARNESS_MODE}" \
  -e ENABLE_FIREWALL="${ENABLE_FIREWALL}" \
  -e OPENAI_ALLOWED_DOMAINS="${OPENAI_ALLOWED_DOMAINS:-api.openai.com}" \
  -v "${WORK_DIR}:/workspace" \
  -w /workspace \
  "${IMAGE_NAME}" "$@"
