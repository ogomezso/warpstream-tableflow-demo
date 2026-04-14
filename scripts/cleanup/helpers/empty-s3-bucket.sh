#!/bin/bash
################################################################################
# Script: empty-s3-bucket.sh
# Description: Empty S3 bucket including all versions and delete markers
################################################################################

set -euo pipefail

BUCKET_NAME="${1:-}"
REGION="${2:-us-east-1}"

if [ -z "$BUCKET_NAME" ]; then
  echo "Usage: $0 <bucket-name> [region]"
  exit 1
fi

echo "Emptying S3 bucket: $BUCKET_NAME (region: $REGION)"

# Check if bucket exists
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$REGION" 2>/dev/null; then
  echo "Bucket does not exist or is not accessible, skipping"
  exit 0
fi

# Delete all object versions
echo "  Deleting all object versions..."
aws s3api list-object-versions \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  --output json \
  --max-items 1000 \
  --query 'Versions[].{Key:Key,VersionId:VersionId}' 2>/dev/null | \
jq -r '.[]? | "  - \(.Key) (version: \(.VersionId))"' | head -20 || true

# Use simpler approach: delete using AWS CLI
aws s3api list-object-versions \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  --output json \
  --query 'Versions[].{Key:Key,VersionId:VersionId}' 2>/dev/null | \
jq -c '.[]?' | \
while IFS= read -r obj; do
  if [ -n "$obj" ]; then
    key=$(echo "$obj" | jq -r '.Key')
    version=$(echo "$obj" | jq -r '.VersionId')
    aws s3api delete-object \
      --bucket "$BUCKET_NAME" \
      --region "$REGION" \
      --key "$key" \
      --version-id "$version" >/dev/null 2>&1 || true
  fi
done

# Delete all delete markers
echo "  Deleting all delete markers..."
aws s3api list-object-versions \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  --output json \
  --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' 2>/dev/null | \
jq -c '.[]?' | \
while IFS= read -r obj; do
  if [ -n "$obj" ]; then
    key=$(echo "$obj" | jq -r '.Key')
    version=$(echo "$obj" | jq -r '.VersionId')
    aws s3api delete-object \
      --bucket "$BUCKET_NAME" \
      --region "$REGION" \
      --key "$key" \
      --version-id "$version" >/dev/null 2>&1 || true
  fi
done

echo "✓ Bucket emptied successfully"
