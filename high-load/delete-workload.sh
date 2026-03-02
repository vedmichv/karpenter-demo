#!/usr/bin/env bash
set -eo pipefail

echo "Deleting all batch deployments..."
kubectl get deploy | grep batch | awk '{print $1}' | xargs kubectl delete deploy
echo "Done."
