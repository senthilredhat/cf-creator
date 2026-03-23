#!/bin/bash

###############################################################################
# Cloud Foundry Restore Script
#
# This script restores the VirtualBox VM state after EC2 startup.
# It is automatically called by systemd after the system boots up.
#
# Manual usage:
#   sudo ./cf-restore.sh
###############################################################################

set -e

# Detect script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
LOG_FILE="/var/log/cf-restore.log"
NOTIFICATION_LOG="/var/log/cf-startup-notifications.log"
STATE_DIR="$SCRIPT_DIR/.state"
BOSH_INTERNAL_IP="192.168.56.6"
CF_NETWORK="10.244.0.0/16"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_notification() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$NOTIFICATION_LOG"
}

notify() {
    local message="$1"
    log_notification "NOTIFICATION: $message"

    # Send to systemd journal
    logger -t cf-restore "$message"

    # Optional SNS notification
    if command -v aws &> /dev/null; then
        # Uncomment and configure if you want SNS notifications
        # aws sns publish --topic-arn "arn:aws:sns:REGION:ACCOUNT:cf-notifications" \
        #   --message "$message" 2>/dev/null || true
        :
    fi
}

main() {
    log "========================================="
    log "Starting Cloud Foundry VM restoration"
    log "========================================="

    notify "🔔 EC2 instance started - Restoring Cloud Foundry"

    # Wait for network to be ready
    log "Waiting for network to be ready..."
    sleep 5

    # Check if VirtualBox is installed
    if ! command -v VBoxManage &> /dev/null; then
        log "ERROR: VBoxManage not found. Is VirtualBox installed?"
        notify "❌ VirtualBox not found - Cannot restore VM"
        exit 1
    fi

    # Check if xmlstarlet is installed
    if ! command -v xmlstarlet &> /dev/null; then
        log "ERROR: xmlstarlet not found. Please install: sudo dnf install xmlstarlet"
        notify "❌ xmlstarlet not found - Cannot restore VM"
        exit 1
    fi

    # Get VM UUID
    log "Detecting VirtualBox VM..."
    VMUUID=$(VBoxManage list vms | grep vm- | awk -F '[{}]' '{ print $2 }' | head -n1)

    if [[ -z "$VMUUID" ]]; then
        log "WARNING: No VirtualBox VM found with prefix 'vm-'"
        notify "⚠️ No Cloud Foundry VM found - Nothing to restore"
        exit 0
    fi

    log "Found VM UUID: $VMUUID"

    # Save UUID for future reference
    echo "$VMUUID" > "$STATE_DIR/vm-uuid"

    # Check current VM state
    VM_STATE=$(VBoxManage showvminfo "vm-$VMUUID" --machinereadable | grep '^VMState=' | cut -d'"' -f2)
    log "Current VM state: $VM_STATE"

    if [[ "$VM_STATE" == "running" ]]; then
        log "VM is already running"
        notify "✅ Cloud Foundry VM already running"
    else
        # Apply the XML fix for VirtualBox issue
        log "Applying VirtualBox configuration fix..."
        VM_DIR=$(VBoxManage showvminfo "vm-$VMUUID" --machinereadable | grep '^CfgFile=' | cut -d'"' -f2 | xargs dirname)
        VM_XML_FILE="$VM_DIR/vm-$VMUUID.vbox"

        if [[ -f "$VM_XML_FILE" ]]; then
            log "Modifying VirtualBox VM configuration: $VM_XML_FILE"
            xmlstarlet edit --inplace -N s=http://www.virtualbox.org/ \
              -u "s:VirtualBox/s:Machine/s:Hardware/s:StorageControllers/s:StorageController[@type='AHCI']/s:AttachedDevice[@port=2]/@hotpluggable" \
              -v "true" "$VM_XML_FILE"
            log "Configuration updated successfully"
        else
            log "WARNING: VM XML file not found: $VM_XML_FILE"
        fi

        # Start the VM
        log "Starting VirtualBox VM in headless mode..."
        notify "🚀 Starting Cloud Foundry VM..."

        if VBoxManage startvm "vm-$VMUUID" --type headless; then
            log "VM started successfully"
            notify "✅ Cloud Foundry VM started"
        else
            log "ERROR: Failed to start VM"
            notify "❌ Failed to start Cloud Foundry VM"
            exit 1
        fi

        # Wait for VM to be fully running
        log "Waiting for VM to be fully operational (30 seconds)..."
        sleep 30
    fi

    # Add network route to CF containers
    log "Configuring network route to Cloud Foundry containers..."
    if ip route | grep -q "$CF_NETWORK"; then
        log "Network route already exists"
    else
        log "Adding route: $CF_NETWORK via $BOSH_INTERNAL_IP"
        if ip route add "$CF_NETWORK" via "$BOSH_INTERNAL_IP" 2>/dev/null; then
            log "Network route added successfully"
        else
            # Try with sudo if direct command fails
            if sudo ip route add "$CF_NETWORK" via "$BOSH_INTERNAL_IP" 2>/dev/null; then
                log "Network route added successfully (with sudo)"
            else
                log "WARNING: Failed to add network route (may already exist)"
            fi
        fi
    fi

    # Verify route
    if ip route | grep -q "$CF_NETWORK"; then
        log "Network route verified: $(ip route | grep $CF_NETWORK)"
    else
        log "WARNING: Network route verification failed"
    fi

    # Test connectivity to BOSH Director
    log "Testing connectivity to BOSH Director ($BOSH_INTERNAL_IP)..."
    if ping -c 1 -W 5 "$BOSH_INTERNAL_IP" &> /dev/null; then
        log "BOSH Director is reachable"
        notify "✅ Cloud Foundry restored and accessible"
    else
        log "WARNING: BOSH Director not reachable yet (may still be booting)"
        notify "⚠️ Cloud Foundry VM started but not yet accessible"
    fi

    # Save restore timestamp
    date +%s > "$STATE_DIR/last-restored"

    log "========================================="
    log "Cloud Foundry VM restoration completed"
    log "========================================="

    notify "🎉 Cloud Foundry restoration complete"
}

# Run main function
main "$@"
