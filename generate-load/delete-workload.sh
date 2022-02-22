#!/bin/bash

set -eo pipefail

kubectl get deploy \
	| grep batch \
	| awk '{print $1}' \
	| xargs kubectl delete deploy 