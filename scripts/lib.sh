#!/usr/bin/env bash
# lib.sh - Shared functions for karpenter-demo scripts
# Source this file: source "$(dirname "$0")/lib.sh"

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "\n${GREEN}==>${NC} ${BLUE}$*${NC}"; }

# Load config.env from repo root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_config() {
  if [[ -f "${REPO_ROOT}/config.env" ]]; then
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/config.env"
  else
    log_error "config.env not found at ${REPO_ROOT}/config.env"
    exit 1
  fi
}

# Generate cluster name with today's date
# Usage: generate_cluster_name "basic" -> "k-basic-26-03-10"
generate_cluster_name() {
  local suffix="$1"
  local date_str
  date_str=$(date +"%y-%m-%d")
  echo "${CLUSTER_PREFIX}-${suffix}-${date_str}"
}

# Wait for a command to succeed with timeout
# Usage: wait_for "kubectl get nodes" 300
wait_for() {
  local cmd="$1"
  local timeout="${2:-120}"
  local interval="${3:-5}"
  local elapsed=0

  while ! eval "$cmd" &>/dev/null; do
    if [[ $elapsed -ge $timeout ]]; then
      log_error "Timed out waiting for: $cmd"
      return 1
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  return 0
}

# Check if a command exists
require_cmd() {
  if ! command -v "$1" &>/dev/null; then
    log_error "Required command not found: $1"
    return 1
  fi
}
