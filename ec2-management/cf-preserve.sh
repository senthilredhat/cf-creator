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

# Detect script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
LOG_FILE="/var/log/cf-preserve.log"
NOTIFICATION_LOG="/var/log/cf-shutdown-notifications.log"
STATE_DIR="$SCRIPT_DIR/.state"

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
    # Detect the actual user who owns the VMs (not root)
    if [[ -n "$SUDO_USER" ]] && [[ "$SUDO_USER" != "root" ]]; then
        VM_USER="$SUDO_USER"
    else
        # Try to find VMs from common users
        for user in fedora sekumar ubuntu ec2-user; do
            if sudo -u "$user" VBoxManage list vms 2>/dev/null | grep -q "vm-"; then
                VM_USER="$user"
                break
            fi
        done
    fi

    log "Detecting VirtualBox VM for user: ${VM_USER:-root}..."

    if [[ -n "$VM_USER" ]]; then
        VMUUID=$(sudo -u "$VM_USER" VBoxManage list vms | grep vm- | awk -F '[{}]' '{ print $2 }' | head -n1)
    else
        VMUUID=$(VBoxManage list vms | grep vm- | awk -F '[{}]' '{ print $2 }' | head -n1)
    fi

    if [[ -z "$VMUUID" ]]; then
        log "WARNING: No VirtualBox VM found with prefix 'vm-'"
        notify "⚠️ No Cloud Foundry VM found - Nothing to preserve"
        exit 0
    fi

    log "Found VM UUID: $VMUUID"

    # Save UUID for restore script
    echo "$VMUUID" > "$STATE_DIR/vm-uuid"

    # Check VM state
    if [[ -n "$VM_USER" ]]; then
        VM_STATE=$(sudo -u "$VM_USER" VBoxManage showvminfo "vm-$VMUUID" --machinereadable | grep '^VMState=' | cut -d'"' -f2)
    else
        VM_STATE=$(VBoxManage showvminfo "vm-$VMUUID" --machinereadable | grep '^VMState=' | cut -d'"' -f2)
    fi
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
    log "Saving VM state (this may take 10-20 minutes for large VMs)..."
    notify "💾 Saving Cloud Foundry VM state (this may take several minutes)..."

    # Record start time
    SAVE_START=$(date +%s)
    log "Save started at $(date)"

    if [[ -n "$VM_USER" ]]; then
        SAVE_CMD="sudo -u $VM_USER VBoxManage controlvm vm-$VMUUID savestate"
    else
        SAVE_CMD="VBoxManage controlvm vm-$VMUUID savestate"
    fi

    if $SAVE_CMD; then
        # Record end time and calculate duration
        SAVE_END=$(date +%s)
        DURATION=$((SAVE_END - SAVE_START))
        log "Save completed at $(date) - Duration: ${DURATION}s ($(($DURATION / 60))m $(($DURATION % 60))s)"

        # Verify VM is actually in saved state
        if [[ -n "$VM_USER" ]]; then
            FINAL_STATE=$(sudo -u "$VM_USER" VBoxManage showvminfo "vm-$VMUUID" --machinereadable | grep '^VMState=' | cut -d'"' -f2)
        else
            FINAL_STATE=$(VBoxManage showvminfo "vm-$VMUUID" --machinereadable | grep '^VMState=' | cut -d'"' -f2)
        fi

        if [[ "$FINAL_STATE" == "saved" ]]; then
            log "Verified: VM state is 'saved'"
            notify "✅ Cloud Foundry VM state saved successfully (took ${DURATION}s)"

            # Save timestamp and duration
            date +%s > "$STATE_DIR/last-saved"
            echo "$DURATION" > "$STATE_DIR/last-save-duration"

            log "Preservation complete"
        else
            log "ERROR: VM state is '$FINAL_STATE', expected 'saved'"
            notify "❌ VM save completed but state verification failed (state: $FINAL_STATE)"
            exit 1
        fi
    else
        SAVE_END=$(date +%s)
        DURATION=$((SAVE_END - SAVE_START))
        log "ERROR: Failed to save VM state after ${DURATION}s"
        notify "❌ Failed to save Cloud Foundry VM state (failed after ${DURATION}s)"
        exit 1
    fi

    log "========================================="
    log "Cloud Foundry VM preservation completed"
    log "========================================="
}

# Run main function
main "$@"
