#!/bin/bash

###############################################################################
# Cloud Foundry Login Script
#
# This script simplifies logging into Cloud Foundry by automatically
# retrieving the admin password from CredHub.
#
# Usage:
#   ./cf-login.sh              # Login with default settings
#   source ./cf-login.sh       # Export environment variables to current shell
###############################################################################

set -e

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
DEPLOYMENTS_DIR="${DEPLOYMENTS_DIR:-$HOME/deployments/vbox}"
CREDHUB_SERVER="${CREDHUB_SERVER:-https://192.168.56.6:8844}"
CF_API_ENDPOINT="${CF_API_ENDPOINT:-https://api.bosh-lite.com}"
CF_USERNAME="${CF_USERNAME:-admin}"

# Ensure ~/.local/bin is in PATH
export PATH="$HOME/.local/bin:$PATH"

echo -e "${BLUE}=== Cloud Foundry Login ===${NC}"

# Configure CredHub environment
echo -e "${BLUE}[1/4] Configuring CredHub environment...${NC}"
export CREDHUB_SERVER="$CREDHUB_SERVER"
export CREDHUB_CLIENT=credhub-admin
export CREDHUB_SECRET=$(bosh int "$DEPLOYMENTS_DIR/creds.yml" --path /credhub_admin_client_secret)
export CREDHUB_CA_CERT="$HOME/credhub-ca.crt"

# Extract CredHub CA certificate if not already present
if [[ ! -f "$CREDHUB_CA_CERT" ]]; then
    echo -e "${YELLOW}Extracting CredHub CA certificate...${NC}"
    bosh int "$DEPLOYMENTS_DIR/creds.yml" --path /credhub_tls/ca > "$CREDHUB_CA_CERT"
fi

# Connect to CredHub
echo -e "${BLUE}[2/4] Connecting to CredHub...${NC}"
credhub api "$CREDHUB_SERVER" --ca-cert="$CREDHUB_CA_CERT" --skip-tls-validation

# Retrieve CF admin password
echo -e "${BLUE}[3/4] Retrieving CF admin password from CredHub...${NC}"
CF_ADMIN_PASSWORD=$(credhub get -n /bosh-lite/cf/cf_admin_password -q)

# Login to Cloud Foundry
echo -e "${BLUE}[4/4] Logging into Cloud Foundry...${NC}"
cf login -a "$CF_API_ENDPOINT" --skip-ssl-validation -u "$CF_USERNAME" -p "$CF_ADMIN_PASSWORD"

echo ""
echo -e "${GREEN}=== Successfully logged into Cloud Foundry ===${NC}"
echo -e "${GREEN}API:${NC} $CF_API_ENDPOINT"
echo -e "${GREEN}User:${NC} $CF_USERNAME"
echo -e "${GREEN}Org:${NC} $(cf target | grep org: | awk '{print $2}')"
echo -e "${GREEN}Space:${NC} $(cf target | grep space: | awk '{print $2}')"
echo ""
echo -e "${YELLOW}Tip: Source this script to keep environment variables in your current shell:${NC}"
echo -e "${YELLOW}  source ./cf-login.sh${NC}"
