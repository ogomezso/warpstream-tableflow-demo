#!/bin/bash

################################################################################
# Script: regions.sh
# Description: Cloud provider and region definitions for WarpStream Tableflow
# Note: Compatible with bash 3.2+ (macOS default)
#
# IMPORTANT: These regions are WarpStream BYOC/TableFlow control plane regions,
# NOT general cloud provider regions. WarpStream only supports specific regions
# for the control plane. Your data/agents/bucket can be in any region, but the
# virtual cluster must be created in one of these supported control plane regions.
#
# Source: WarpStream internal documentation (via Glean)
################################################################################

# Get sorted region list for a cloud provider
get_regions_for_provider() {
  local provider="$1"

  case "$provider" in
    aws)
      # WarpStream BYOC/TableFlow control plane supported regions
      echo "ap-northeast-1
ap-south-1
ap-southeast-1
ap-southeast-2
eu-central-1
eu-west-1
us-east-1
us-east-2
us-west-2"
      ;;
    azure)
      # WarpStream BYOC/TableFlow control plane supported regions
      # Note: Azure only has one control plane region
      echo "eastus"
      ;;
    gcp)
      # WarpStream BYOC/TableFlow control plane supported regions
      echo "asia-south1
europe-west1
northamerica-northeast1
us-central1"
      ;;
    *)
      echo "Error: Unknown provider: $provider" >&2
      return 1
      ;;
  esac
}

# Get region description
get_region_description() {
  local provider="$1"
  local region="$2"

  case "$provider" in
    aws)
      case "$region" in
        us-east-1) echo "US East (N. Virginia)" ;;
        us-east-2) echo "US East (Ohio)" ;;
        us-west-2) echo "US West (Oregon)" ;;
        eu-west-1) echo "Europe (Ireland)" ;;
        eu-central-1) echo "Europe (Frankfurt)" ;;
        ap-southeast-1) echo "Asia Pacific (Singapore)" ;;
        ap-southeast-2) echo "Asia Pacific (Sydney)" ;;
        ap-south-1) echo "Asia Pacific (Mumbai)" ;;
        ap-northeast-1) echo "Asia Pacific (Tokyo)" ;;
        *) echo "Unknown region" ;;
      esac
      ;;
    azure)
      case "$region" in
        eastus) echo "East US (WarpStream control plane region)" ;;
        *) echo "Unknown region" ;;
      esac
      ;;
    gcp)
      case "$region" in
        us-central1) echo "US Central (Iowa)" ;;
        northamerica-northeast1) echo "North America Northeast (Montreal)" ;;
        europe-west1) echo "Europe West (Belgium)" ;;
        asia-south1) echo "Asia South (Mumbai)" ;;
        *) echo "Unknown region" ;;
      esac
      ;;
    *)
      echo "Unknown"
      ;;
  esac
}

# Default regions per provider
get_default_region() {
  local provider="$1"

  case "$provider" in
    aws)
      echo "us-east-1"
      ;;
    azure)
      echo "eastus"
      ;;
    gcp)
      echo "us-central1"
      ;;
    *)
      echo ""
      ;;
  esac
}
