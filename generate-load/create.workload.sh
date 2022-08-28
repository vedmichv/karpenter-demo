#!/bin/bash

set -o pipefail

# total amount of pods to create
TOTAL=${1:-500}
# deploy size
export BATCH=${2:-100}
export SECONDS=${3:0}
export NAMESPACE=${4:-default}

CPU_OPTIONS=(250m 500m 750m 1 2)
MEM_OPTIONS=(128M 256M 512M 750M 1G)
# MEM_OPTIONS=(256M 512M 750M 1G 1500M)

CPU_OPTIONS_LENG=${#CPU_OPTIONS[@]}
MEM_OPTIONS_LENG=${#MEM_OPTIONS[@]}

COUNT=0
while (test $COUNT -lt $TOTAL); do
	RAND=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 5 | head -n 1)
	export CPU=${CPU_OPTIONS[$[$RANDOM % $CPU_OPTIONS_LENG]]}
	export MEM=${MEM_OPTIONS[$[$RANDOM % $MEM_OPTIONS_LENG]]}
	export NAME="batch-${CPU,,}-${MEM,,}-${RAND}"
	echo "Creating ${NAME} with ${BATCH} replicas"
	cat deployment-template.yaml \
		| envsubst \
		| kubectl apply -n ${NAMESPACE} -f -
	COUNT=$((COUNT+$BATCH))
	sleep ${SECONDS}
done