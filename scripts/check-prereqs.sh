#!/usr/bin/env bash
# check-prereqs.sh - Verify all required tools are installed
source "$(dirname "$0")/lib.sh"
load_config

log_step "Checking prerequisites"

ERRORS=0

for cmd in kubectl eksctl helm aws; do
  if require_cmd "$cmd"; then
    local_ver=""
    case "$cmd" in
      kubectl) local_ver=$(kubectl version --client 2>/dev/null | head -1) ;;
      eksctl)  local_ver=$(eksctl version 2>/dev/null) ;;
      helm)    local_ver=$(helm version --short 2>/dev/null) ;;
      aws)     local_ver=$(aws --version 2>/dev/null) ;;
    esac
    log_ok "$cmd: ${local_ver:-unknown}"
  else
    ERRORS=$((ERRORS + 1))
  fi
done

# Check AWS credentials
log_info "Checking AWS credentials..."
if aws sts get-caller-identity &>/dev/null; then
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  log_ok "AWS Account: ${AWS_ACCOUNT_ID}"
else
  log_error "AWS credentials not configured. Run 'aws configure' or set AWS_PROFILE"
  ERRORS=$((ERRORS + 1))
fi

# Check region
log_info "Region: ${AWS_DEFAULT_REGION}"

if [[ $ERRORS -gt 0 ]]; then
  log_error "${ERRORS} prerequisite(s) missing. Install them and retry."
  exit 1
fi

log_ok "All prerequisites satisfied"
