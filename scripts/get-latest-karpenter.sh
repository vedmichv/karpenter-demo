#!/usr/bin/env bash
# get-latest-karpenter.sh - Fetch latest Karpenter version from GitHub/Helm
# Outputs the version string (e.g., "1.8.2") to stdout
source "$(dirname "$0")/lib.sh"
load_config

# Try to get latest version from GitHub releases API (most reliable)
get_from_github() {
  curl -fsSL "https://api.github.com/repos/aws/karpenter-provider-aws/releases/latest" 2>/dev/null \
    | grep '"tag_name"' \
    | sed -E 's/.*"v([^"]+)".*/\1/'
}

# Try to get from Helm OCI registry
get_from_helm() {
  helm show chart oci://public.ecr.aws/karpenter/karpenter 2>/dev/null \
    | grep '^version:' \
    | awk '{print $2}'
}

VERSION=""

# Method 1: GitHub releases
VERSION=$(get_from_github)

# Method 2: Helm registry
if [[ -z "$VERSION" ]]; then
  log_warn "GitHub API failed, trying Helm registry..." >&2
  VERSION=$(get_from_helm)
fi

# Fallback to config
if [[ -z "$VERSION" ]]; then
  log_warn "Could not fetch latest version, using fallback: ${KARPENTER_VERSION_FALLBACK}" >&2
  VERSION="${KARPENTER_VERSION_FALLBACK}"
fi

echo "$VERSION"
