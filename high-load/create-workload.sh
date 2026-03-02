#!/usr/bin/env bash
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE="${REPO_ROOT}/manifests/highload/deployment-template.yaml"

# total amount of pods to create
TOTAL=${1:-500}
# deploy size
export BATCH=${2:-100}
export NAMESPACE=${3:-default}

echo "Performance test: create"
echo "- ${TOTAL} pods, ${BATCH} batch in ${NAMESPACE} namespace"

CPU_OPTIONS=(250m 500m 750m 1 2)
MEM_OPTIONS=(128M 256M 512M 750M 1G)

CPU_OPTIONS_LENG=${#CPU_OPTIONS[@]}
MEM_OPTIONS_LENG=${#MEM_OPTIONS[@]}

COUNT=0
while (test $COUNT -lt $TOTAL); do
  RAND=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 5)
  export CPU=${CPU_OPTIONS[$((RANDOM % CPU_OPTIONS_LENG))]}
  export MEM=${MEM_OPTIONS[$((RANDOM % MEM_OPTIONS_LENG))]}
  CPU_LOWER=$(echo "$CPU" | tr '[:upper:]' '[:lower:]')
  MEM_LOWER=$(echo "$MEM" | tr '[:upper:]' '[:lower:]')
  export NAME="batch-${CPU_LOWER}-${MEM_LOWER}-${RAND}"
  echo "Creating ${NAME} with ${BATCH} replicas"
  envsubst < "${TEMPLATE}" | kubectl apply -n "${NAMESPACE}" -f -
  COUNT=$((COUNT + BATCH))
done
