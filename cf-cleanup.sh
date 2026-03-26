#!/bin/bash

###############################################################################
# Cloud Foundry Cleanup Script
#
# This script cleans up Cloud Foundry deployment artifacts and allows you
# to restart from specific phases.
#
# Usage:
#   ./cf-cleanup.sh --from phase4    # Clean and restart from phase4_vbox_networking
#   ./cf-cleanup.sh --from phase5    # Clean and restart from phase5_bosh_deployment
#   ./cf-cleanup.sh --full           # Complete cleanup (like 'reset')
#   ./cf-cleanup.sh --help           # Show help
###############################################################################

set -e  # Exit on any error
set -o pipefail  # Catch errors in pipes

# Configuration
STATE_FILE="$HOME/.cf-deployment-state"
LOG_FILE="$PWD/cf-deployment.log"
WORKSPACE_DIR="$HOME/workspace"
DEPLOYMENTS_DIR="$HOME/deployments/vbox"
CF_DEPLOYMENT_DIR="$HOME/cf-deployment"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###############################################################################
# Helper Functions
###############################################################################

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠${NC} $*" | tee -a "$LOG_FILE"
}

confirm_action() {
    local message=$1
    echo -e "${YELLOW}${message}${NC}"
    echo -e "${YELLOW}Are you sure you want to proceed? (yes/no)${NC}"
    read -r response
    if [[ "$response" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

###############################################################################
# Cleanup Functions
###############################################################################

cleanup_cf_deployment() {
    log "=== Cleaning up Cloud Foundry deployment ==="

    export PATH="$HOME/.local/bin:$PATH"

    # Check if BOSH is available and try to delete CF deployment
    if command -v bosh &> /dev/null; then
        if [[ -f "$DEPLOYMENTS_DIR/creds.yml" ]]; then
            export BOSH_CLIENT=admin
            export BOSH_CLIENT_SECRET=$(bosh int "$DEPLOYMENTS_DIR/creds.yml" --path /admin_password 2>/dev/null || echo "")

            if [[ -n "$BOSH_CLIENT_SECRET" ]]; then
                log "Attempting to delete CF deployment..."
                bosh -e vbox -d cf delete-deployment --force -n 2>/dev/null || log_warning "Could not delete CF deployment (may not exist)"
            fi
        fi
    fi

    # Remove CF deployment directory
    if [[ -d "$CF_DEPLOYMENT_DIR" ]]; then
        log "Removing CF deployment directory: $CF_DEPLOYMENT_DIR"
        rm -rf "$CF_DEPLOYMENT_DIR"
        log_success "CF deployment directory removed"
    fi

    # Remove CF hosts entries
    if grep -q "bosh-lite.com" /etc/hosts 2>/dev/null; then
        log "Removing CF hosts entries..."
        sudo sed -i '/bosh-lite.com/d' /etc/hosts
        log_success "CF hosts entries removed"
    fi

    log_success "CF deployment cleanup completed"
}

cleanup_bosh_deployment() {
    log "=== Cleaning up BOSH deployment ==="

    export PATH="$HOME/.local/bin:$PATH"

    # Force remove any BOSH VMs in VirtualBox
    log "Checking for BOSH VMs in VirtualBox..."
    VBoxManage list vms 2>/dev/null | grep -i bosh | cut -d'"' -f2 | while read -r vm_name; do
        log "Force removing VM: $vm_name"
        VBoxManage controlvm "$vm_name" poweroff 2>/dev/null || true
        sleep 2
        VBoxManage unregistervm "$vm_name" --delete 2>/dev/null || true
        log_success "VM removed: $vm_name"
    done

    # Remove IP route
    if ip route | grep -q "10.244.0.0/16 via 192.168.56.6"; then
        log "Removing BOSH container network route..."
        sudo ip route del 10.244.0.0/16 via 192.168.56.6 2>/dev/null || log_warning "Route already removed"
        log_success "BOSH route removed"
    fi

    # Remove deployments directory
    if [[ -d "$DEPLOYMENTS_DIR" ]]; then
        log "Removing deployments directory: $DEPLOYMENTS_DIR"
        rm -rf "$DEPLOYMENTS_DIR"
        log_success "Deployments directory removed"
    fi

    # Remove bosh-deployment checkout
    if [[ -d "$WORKSPACE_DIR/bosh-deployment" ]]; then
        log "Removing bosh-deployment repository: $WORKSPACE_DIR/bosh-deployment"
        rm -rf "$WORKSPACE_DIR/bosh-deployment"
        log_success "bosh-deployment repository removed"
    fi

    # Remove CredHub CA cert
    if [[ -f "$HOME/credhub-ca.crt" ]]; then
        log "Removing CredHub CA certificate..."
        rm -f "$HOME/credhub-ca.crt"
        log_success "CredHub CA certificate removed"
    fi

    # Remove BOSH alias
    if command -v bosh &> /dev/null; then
        log "Removing BOSH environment alias..."
        bosh delete-env vbox 2>/dev/null || true
    fi

    log_success "BOSH deployment cleanup completed"
}

cleanup_vbox_networking() {
    log "=== Cleaning up VirtualBox networking ==="

    # Remove host-only network interface
    if VBoxManage list hostonlyifs 2>/dev/null | grep -q "vboxnet0"; then
        log "Removing host-only network interface vboxnet0..."
        VBoxManage hostonlyif remove vboxnet0 2>/dev/null || log_warning "Could not remove vboxnet0"
        log_success "Host-only interface removed"
    fi

    # Remove NAT network
    if VBoxManage list natnetworks 2>/dev/null | grep -q "NatNetwork"; then
        log "Removing NAT network NatNetwork..."
        VBoxManage natnetwork remove --netname NatNetwork 2>/dev/null || log_warning "Could not remove NatNetwork"
        log_success "NAT network removed"
    fi

    # Check for any other lingering VirtualBox networks
    log "Checking for other VirtualBox resources..."

    # List all VMs (should be none after cleanup)
    local vms=$(VBoxManage list vms 2>/dev/null | wc -l)
    if [[ $vms -gt 0 ]]; then
        log_warning "Warning: $vms VirtualBox VM(s) still exist"
        VBoxManage list vms
    fi

    # List all running VMs
    local running_vms=$(VBoxManage list runningvms 2>/dev/null | wc -l)
    if [[ $running_vms -gt 0 ]]; then
        log_warning "Warning: $running_vms VirtualBox VM(s) still running"
        VBoxManage list runningvms
    fi

    log_success "VirtualBox networking cleanup completed"
}

reset_checkpoint() {
    local phase=$1
    log "Resetting checkpoint to before: $phase"

    if [[ -f "$STATE_FILE" ]]; then
        # Remove the phase and all phases after it from the state file
        sed -i "/^$phase$/,\$d" "$STATE_FILE"
        log_success "Checkpoint reset to before $phase"
    else
        log_warning "No state file found"
    fi
}

show_help() {
    cat << EOF
${BLUE}Cloud Foundry Cleanup Script${NC}

This script cleans up CF deployment artifacts and prepares for restart from specific phases.

${GREEN}Usage:${NC}
  $0 --from phase4    Clean everything from phase4 onwards (VBox networking, BOSH, CF)
  $0 --from phase5    Clean everything from phase5 onwards (BOSH and CF, keep networking)
  $0 --full           Complete cleanup (removes all artifacts)
  $0 --help           Show this help message

${GREEN}Cleanup Levels:${NC}
  ${YELLOW}--from phase4${NC} (phase4_vbox_networking):
    - Removes VirtualBox NAT network and host-only interface
    - Removes BOSH Director VM
    - Removes deployments/vbox directory
    - Removes bosh-deployment and cf-deployment checkouts
    - Removes BOSH container network route
    - Resets state file to before phase4
    ${BLUE}Use this when:${NC} VBox networking has issues or you want a complete network reset

  ${YELLOW}--from phase5${NC} (phase5_bosh_deployment):
    - Keeps VirtualBox networking intact
    - Removes BOSH Director VM
    - Removes deployments/vbox directory
    - Removes bosh-deployment and cf-deployment checkouts
    - Removes BOSH container network route
    - Resets state file to before phase5
    ${BLUE}Use this when:${NC} BOSH or CF deployment fails but networking is fine

  ${YELLOW}--full${NC}:
    - Removes everything (same as --from phase4)
    - Completely resets the deployment

${GREEN}After Cleanup:${NC}
  Run ${BLUE}./deploy-cf.sh${NC} to restart from the appropriate phase

${GREEN}Examples:${NC}
  # VBox networking is misconfigured, start fresh from phase4
  $0 --from phase4

  # BOSH deployment failed, retry from phase5
  $0 --from phase5

  # Complete reset
  $0 --full

EOF
}

###############################################################################
# Main Script Logic
###############################################################################

main() {
    local cleanup_level=""

    case "${1:-}" in
        --from)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 --from [phase4|phase5]"
                exit 1
            fi
            cleanup_level="$2"
            ;;
        --full)
            cleanup_level="full"
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Invalid option: ${1:-}"
            echo ""
            show_help
            exit 1
            ;;
    esac

    log "==================================================="
    log "Cloud Foundry Cleanup Script"
    log "==================================================="
    log "Cleanup level: $cleanup_level"
    echo ""

    case "$cleanup_level" in
        phase4|phase4_vbox_networking)
            confirm_action "This will clean up VBox networking, BOSH, and CF deployments."
            echo ""
            cleanup_cf_deployment
            cleanup_bosh_deployment
            cleanup_vbox_networking
            reset_checkpoint "phase4_vbox_networking"
            echo ""
            log_success "==================================================="
            log_success "Cleanup completed! Ready to restart from phase4"
            log_success "==================================================="
            log "Run: ./deploy-cf.sh"
            ;;
        phase5|phase5_bosh_deployment)
            confirm_action "This will clean up BOSH and CF deployments (keeps VBox networking)."
            echo ""
            cleanup_cf_deployment
            cleanup_bosh_deployment
            reset_checkpoint "phase5_bosh_deployment"
            echo ""
            log_success "==================================================="
            log_success "Cleanup completed! Ready to restart from phase5"
            log_success "==================================================="
            log "VBox networking preserved (vboxnet0, NatNetwork)"
            log "Run: ./deploy-cf.sh"
            ;;
        full)
            confirm_action "This will perform a COMPLETE cleanup of all CF deployment artifacts."
            echo ""
            cleanup_cf_deployment
            cleanup_bosh_deployment
            cleanup_vbox_networking
            if [[ -f "$STATE_FILE" ]]; then
                rm -f "$STATE_FILE"
                log_success "State file removed"
            fi
            echo ""
            log_success "==================================================="
            log_success "Complete cleanup finished!"
            log_success "==================================================="
            log "Run: ./deploy-cf.sh to start from the beginning"
            ;;
        *)
            log_error "Invalid cleanup level: $cleanup_level"
            log_error "Valid options: phase4, phase5, full"
            exit 1
            ;;
    esac

    echo ""
    log "Check status with: ./deploy-cf.sh status"
}

# Error handler
error_handler() {
    log_error "An error occurred on line $1"
    log_error "Some cleanup steps may have failed. Please check the log."
    log_error "You may need to manually clean up some resources."
    exit 1
}

trap 'error_handler $LINENO' ERR

# Run main function
main "$@"
