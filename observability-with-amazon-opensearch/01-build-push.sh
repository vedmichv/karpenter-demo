#!/bin/bash
#
# CloudShell-compatible replacement for 01-build-push.sh
# Changes from original:
#   - Removed IMDS-based region/account detection (uses env vars from setup)
#   - Removed Docker login (not available in CloudShell; builds use CodeBuild)
#   - Added --region flags to all AWS CLI calls
#   - Added validation and error handling
#
# Prerequisites:
#   - Run cloudshell-00-setup.sh first (sets AWS_REGION, ACCOUNT_ID, etc.)
#   - Workshop CloudFormation stack deployed (creates OSIS pipelines, CodeBuild projects, S3 bucket)
#
# Usage:
#   cd ~/observability-with-amazon-opensearch/scripts
#   bash cloudshell-01-build-push.sh
#

set -euo pipefail

# ── Validate prerequisites ───────────────────────────────────────────────────
if [ -z "${AWS_REGION:-}" ] || [ -z "${ACCOUNT_ID:-}" ]; then
    echo "ERROR: AWS_REGION or ACCOUNT_ID not set."
    echo "Run cloudshell-00-setup.sh first, then: source ~/.bash_profile"
    exit 1
fi

echo "==> AWS_REGION=$AWS_REGION  ACCOUNT_ID=$ACCOUNT_ID"

# ── Obtain OSIS pipeline endpoints ──────────────────────────────────────────
echo "==> Fetching OpenSearch Ingestion pipeline endpoints..."
export OSIS_TRACES_URL=$(aws osis get-pipeline --region $AWS_REGION --pipeline-name osi-pipeline-oteltraces | jq -r '.Pipeline.IngestEndpointUrls[0]')
export OSIS_LOGS_URL=$(aws osis get-pipeline --region $AWS_REGION --pipeline-name osi-pipeline-otellogs | jq -r '.Pipeline.IngestEndpointUrls[0]')
export OSIS_METRICS_URL=$(aws osis get-pipeline --region $AWS_REGION --pipeline-name osi-pipeline-otelmetrics | jq -r '.Pipeline.IngestEndpointUrls[0]')

echo "    Traces:  $OSIS_TRACES_URL"
echo "    Logs:    $OSIS_LOGS_URL"
echo "    Metrics: $OSIS_METRICS_URL"

if [ -z "$OSIS_TRACES_URL" ] || [ "$OSIS_TRACES_URL" = "null" ]; then
    echo "ERROR: OSIS pipelines not found. Is the CloudFormation stack fully deployed?"
    echo "Check: aws osis list-pipelines --region $AWS_REGION"
    exit 1
fi

# ── Configure OTel collector configmap with OSIS endpoints ───────────────────
cd "$(dirname "$0")/.."
echo "==> Configuring OTel collector configmap..."

CONFIGMAP="sample-apps/02-otel-collector/kubernetes/01-configmap.yaml"
sed -i "s|__REPLACE_WITH_OtelTraces_ENDPOINT__|${OSIS_TRACES_URL}|g" "$CONFIGMAP"
sed -i "s|__REPLACE_WITH_OtelLogs_ENDPOINT__|${OSIS_LOGS_URL}|g" "$CONFIGMAP"
sed -i "s|__REPLACE_WITH_OtelMetrics_ENDPOINT__|${OSIS_METRICS_URL}|g" "$CONFIGMAP"
sed -i "s|__AWS_REGION__|${AWS_REGION}|g" "$CONFIGMAP"

# ── Build and push functions ─────────────────────────────────────────────────
push_images_s3() {
    local service_folder=$1
    local repo_name=$2

    echo "==> Building ${repo_name} ..."
    cd "sample-apps/${service_folder}/"
    echo "    Working dir: $PWD"

    # Zip source and upload to S3 for CodeBuild
    zip -rq "${repo_name}.zip" ./*
    aws s3 cp "${repo_name}.zip" "s3://codebuild-assets-${AWS_REGION}-${ACCOUNT_ID}/" --region "$AWS_REGION"
    rm "${repo_name}.zip"

    # Substitute placeholders in Kubernetes deployment manifest
    sed -i "s|__ACCOUNT_ID__|${ACCOUNT_ID}|g" kubernetes/01-deployment.yaml
    sed -i "s|__AWS_REGION__|${AWS_REGION}|g" kubernetes/01-deployment.yaml
    rm -f kubernetes/01-deployment.yaml-e

    # Trigger CodeBuild
    sleep 5
    aws codebuild start-build --project-name "$repo_name" --region "$AWS_REGION" > /dev/null
    echo "    ✓ Build triggered for $repo_name"

    cd ../..
}

check_build_status() {
    echo ""
    echo "==> Waiting for CodeBuild projects to complete..."
    local projects
    projects=$(aws codebuild list-projects --region "$AWS_REGION" --output text --query 'projects[*]')
    local remaining=($projects)

    while [ ${#remaining[@]} -gt 0 ]; do
        local still_building=()
        for project in "${remaining[@]}"; do
            local build_id
            build_id=$(aws codebuild list-builds-for-project --project-name "$project" --region "$AWS_REGION" --output text --query 'ids[0]' 2>/dev/null)
            if [ -z "$build_id" ] || [ "$build_id" = "None" ]; then
                continue
            fi
            local status
            status=$(aws codebuild batch-get-builds --ids "$build_id" --region "$AWS_REGION" --query 'builds[0].buildStatus' --output text 2>/dev/null)
            if [ "$status" != "SUCCEEDED" ] && [ "$status" != "FAILED" ] && [ "$status" != "STOPPED" ]; then
                still_building+=("$project")
            elif [ "$status" = "FAILED" ]; then
                echo "    ✗ FAILED: $project"
            fi
        done
        remaining=("${still_building[@]+"${still_building[@]}"}")
        if [ ${#remaining[@]} -gt 0 ]; then
            echo "    Still building: ${remaining[*]}"
            sleep 15
        fi
    done
    echo "==> All builds complete!"
}

# ── Trigger all builds ───────────────────────────────────────────────────────
push_images_s3 '04-analytics-service' 'analytics-service'
push_images_s3 '05-databaseService' 'database-service'
push_images_s3 '06-orderService' 'order-service'
push_images_s3 '07-inventoryService' 'inventory-service'
push_images_s3 '08-paymentService' 'payment-service'
push_images_s3 '09-recommendationService' 'recommendation-service'
push_images_s3 '10-authenticationService' 'authentication-service'
push_images_s3 '11-client' 'client-service'

# ── Wait for all builds ──────────────────────────────────────────────────────
check_build_status
