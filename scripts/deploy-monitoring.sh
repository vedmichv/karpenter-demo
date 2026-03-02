#!/usr/bin/env bash
# deploy-monitoring.sh - Deploy metrics-server and kube-ops-view
source "$(dirname "$0")/lib.sh"

log_step "Deploying monitoring stack"

# Step 1: metrics-server
log_info "Installing metrics-server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
log_ok "metrics-server deployed"

# Step 2: kube-ops-view
log_info "Installing kube-ops-view..."
kubectl apply -k "${REPO_ROOT}/manifests/monitoring/kube-ops-view"
log_ok "kube-ops-view deployed"

# Wait for kube-ops-view to become ready
log_info "Waiting for kube-ops-view pods..."
kubectl wait --for=condition=ready pod -l application=kube-ops-view,component=frontend --timeout=120s 2>/dev/null || true

# Get LoadBalancer URL
log_info "Getting kube-ops-view URL (may take a minute for ELB)..."
KOV_URL=""
for i in $(seq 1 30); do
  KOV_URL=$(kubectl get svc kube-ops-view -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  if [[ -n "$KOV_URL" ]]; then
    break
  fi
  sleep 5
done

if [[ -n "$KOV_URL" ]]; then
  log_ok "kube-ops-view URL: http://${KOV_URL}"
  echo "$KOV_URL"
else
  log_warn "LoadBalancer URL not yet available. Check with: kubectl get svc kube-ops-view"
fi
