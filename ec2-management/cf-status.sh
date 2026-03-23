#!/bin/bash

###############################################################################
# Cloud Foundry Status Checker
#
# This script checks the status of Cloud Foundry VM and services.
#
# Usage:
#   ./cf-status.sh
###############################################################################

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

STATE_DIR="/home/sekumar/.cf-vm-state"
BOSH_INTERNAL_IP="192.168.56.6"
CF_API="https://api.bosh-lite.com"

print_header() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=========================================${NC}"
}

print_status() {
    local status=$1
    local message=$2
    if [[ "$status" == "ok" ]]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [[ "$status" == "warning" ]]; then
        echo -e "${YELLOW}⚠${NC} $message"
    else
        echo -e "${RED}✗${NC} $message"
    fi
}

print_info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

main() {
    print_header "Cloud Foundry System Status"
    echo ""

    # Check VirtualBox
    echo -e "${YELLOW}VirtualBox Status:${NC}"
    if ! command -v VBoxManage &> /dev/null; then
        print_status "error" "VirtualBox not installed"
    else
        print_status "ok" "VirtualBox installed"

        # Check for VM
        VMUUID=$(VBoxManage list vms | grep vm- | awk -F '[{}]' '{ print $2 }' | head -n1)
        if [[ -z "$VMUUID" ]]; then
            print_status "warning" "No Cloud Foundry VM found"
        else
            print_status "ok" "VM found: vm-$VMUUID"

            # Get VM state
            VM_STATE=$(VBoxManage showvminfo "vm-$VMUUID" --machinereadable | grep '^VMState=' | cut -d'"' -f2)
            if [[ "$VM_STATE" == "running" ]]; then
                print_status "ok" "VM State: Running"
            elif [[ "$VM_STATE" == "saved" ]]; then
                print_status "warning" "VM State: Saved (not running)"
            else
                print_status "error" "VM State: $VM_STATE"
            fi
        fi
    fi

    echo ""

    # Check systemd services
    echo -e "${YELLOW}Systemd Services:${NC}"
    if systemctl is-enabled cf-preserve.service &> /dev/null; then
        print_status "ok" "cf-preserve.service enabled"
    else
        print_status "error" "cf-preserve.service not enabled"
    fi

    if systemctl is-enabled cf-restore.service &> /dev/null; then
        print_status "ok" "cf-restore.service enabled"
    else
        print_status "error" "cf-restore.service not enabled"
    fi

    echo ""

    # Check network connectivity
    echo -e "${YELLOW}Network Status:${NC}"
    if ip route | grep -q "10.244.0.0/16"; then
        print_status "ok" "CF network route configured"
        print_info "Route: $(ip route | grep 10.244.0.0/16)"
    else
        print_status "error" "CF network route not configured"
    fi

    if ping -c 1 -W 2 "$BOSH_INTERNAL_IP" &> /dev/null; then
        print_status "ok" "BOSH Director reachable ($BOSH_INTERNAL_IP)"
    else
        print_status "error" "BOSH Director not reachable ($BOSH_INTERNAL_IP)"
    fi

    echo ""

    # Check Cloud Foundry
    echo -e "${YELLOW}Cloud Foundry Status:${NC}"
    if command -v cf &> /dev/null; then
        print_status "ok" "CF CLI installed"

        # Check if logged in
        if cf target &> /dev/null; then
            print_status "ok" "Logged into CF"
            print_info "$(cf target | grep -E '(api|org|space):')"
        else
            print_status "warning" "Not logged into CF"
        fi
    else
        print_status "error" "CF CLI not installed"
    fi

    echo ""

    # Check state files
    echo -e "${YELLOW}State Information:${NC}"
    if [[ -f "$STATE_DIR/vm-uuid" ]]; then
        SAVED_UUID=$(cat "$STATE_DIR/vm-uuid")
        print_status "ok" "Saved VM UUID: $SAVED_UUID"
    else
        print_status "warning" "No saved VM UUID"
    fi

    if [[ -f "$STATE_DIR/last-saved" ]]; then
        LAST_SAVED=$(date -d @$(cat "$STATE_DIR/last-saved") 2>/dev/null || echo "unknown")
        print_info "Last saved: $LAST_SAVED"
    fi

    if [[ -f "$STATE_DIR/last-restored" ]]; then
        LAST_RESTORED=$(date -d @$(cat "$STATE_DIR/last-restored") 2>/dev/null || echo "unknown")
        print_info "Last restored: $LAST_RESTORED"
    fi

    echo ""

    # Check recent notifications
    echo -e "${YELLOW}Recent Notifications:${NC}"
    if [[ -f "/var/log/cf-shutdown-notifications.log" ]]; then
        RECENT_SHUTDOWN=$(tail -n 1 /var/log/cf-shutdown-notifications.log 2>/dev/null)
        if [[ -n "$RECENT_SHUTDOWN" ]]; then
            print_info "Last shutdown: $RECENT_SHUTDOWN"
        fi
    fi

    if [[ -f "/var/log/cf-startup-notifications.log" ]]; then
        RECENT_STARTUP=$(tail -n 1 /var/log/cf-startup-notifications.log 2>/dev/null)
        if [[ -n "$RECENT_STARTUP" ]]; then
            print_info "Last startup: $RECENT_STARTUP"
        fi
    fi

    echo ""

    # Overall status
    print_header "Overall Status"
    if [[ -n "$VMUUID" ]] && [[ "$VM_STATE" == "running" ]] && ping -c 1 -W 2 "$BOSH_INTERNAL_IP" &> /dev/null; then
        print_status "ok" "Cloud Foundry is operational"
    else
        print_status "warning" "Cloud Foundry may not be fully operational"
    fi

    echo ""
}

main "$@"
