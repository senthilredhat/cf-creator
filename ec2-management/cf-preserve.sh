#!/bin/bash

###############################################################################
# Cloud Foundry Preserve Script
#
# This script saves the VirtualBox VM state before EC2 shutdown.
# It is automatically called by systemd before the system shuts down.
#
# Manual usage:
#   sudo ./cf-preserve.sh
###############################################################################

set -e

# Configuration
LOG_FILE="/var/log/cf-preserve.log"
NOTIFICATION_LOG="/var/log/cf-shutdown-notifications.log"
STATE_DIR="/home/sekumar/.cf-vm-state"

# Ensure state directory exists
mkdir -p "$STATE_DIR"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_notification() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$NOTIFICATION_LOG"
}

notify() {
    local message="$1"
    log_notification "NOTIFICATION: $message"

    # Also send to systemd journal for centralized logging
    logger -t cf-preserve "$message"

    # If AWS CLI is available, can send to SNS (optional)
    if command -v aws &> /dev/null; then
        # Uncomment and configure if you want SNS notifications
        # aws sns publish --topic-arn "arn:aws:sns:REGION:ACCOUNT:cf-notifications" \
        #   --message "$message" 2>/dev/null || true
        :
    fi
}

main() {
    log "========================================="
    log "Starting Cloud Foundry VM preservation"
    log "========================================="

    notify "🔔 Cloud Foundry shutdown initiated - Preserving VM state"

    # Check if VirtualBox is installed
    if ! command -v VBoxManage &> /dev/null; then
        log "ERROR: VBoxManage not found. Is VirtualBox installed?"
        notify "❌ VirtualBox not found - Cannot preserve VM state"
        exit 1
    fi

    # Get VM UUID
    log "Detecting VirtualBox VM..."
    VMUUID=$(VBoxManage list vms | grep vm- | awk -F '[{}]' '{ print $2 }' | head -n1)

    if [[ -z "$VMUUID" ]]; then
        log "WARNING: No VirtualBox VM found with prefix 'vm-'"
        notify "⚠️ No Cloud Foundry VM found - Nothing to preserve"
        exit 0
    fi

    log "Found VM UUID: $VMUUID"

    # Save UUID for restore script
    echo "$VMUUID" > "$STATE_DIR/vm-uuid"

    # Check VM state
    VM_STATE=$(VBoxManage showvminfo "vm-$VMUUID" --machinereadable | grep '^VMState=' | cut -d'"' -f2)
    log "Current VM state: $VM_STATE"

    if [[ "$VM_STATE" == "saved" ]]; then
        log "VM is already in saved state"
        notify "✅ Cloud Foundry VM already saved"
        exit 0
    fi

    if [[ "$VM_STATE" == "poweroff" ]] || [[ "$VM_STATE" == "aborted" ]]; then
        log "VM is already powered off"
        notify "✅ Cloud Foundry VM already stopped"
        exit 0
    fi

    # Save VM state
    log "Saving VM state (this may take a few seconds)..."
    notify "💾 Saving Cloud Foundry VM state..."

    if VBoxManage controlvm "vm-$VMUUID" savestate; then
        log "Successfully saved VM state"
        notify "✅ Cloud Foundry VM state saved successfully"

        # Save timestamp
        date +%s > "$STATE_DIR/last-saved"

        log "Preservation complete"
    else
        log "ERROR: Failed to save VM state"
        notify "❌ Failed to save Cloud Foundry VM state"
        exit 1
    fi

    log "========================================="
    log "Cloud Foundry VM preservation completed"
    log "========================================="
}

# Run main function
main "$@"
