#!/bin/bash

###############################################################################
# Test VirtualBox VM User Detection Fix
#
# This script verifies that VM detection works correctly both as regular
# user and as root (with sudo).
###############################################################################

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}VirtualBox VM User Detection Test${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Test 1: Current user info
echo -e "${YELLOW}Test 1: Current User Information${NC}"
echo "Current user: $(whoami)"
echo "Current UID: $(id -u)"
echo "SUDO_USER: ${SUDO_USER:-not set}"
echo ""

# Test 2: VBoxManage as current user
echo -e "${YELLOW}Test 2: VBoxManage as Current User${NC}"
echo "Running: VBoxManage list vms | grep vm-"
if VBoxManage list vms 2>/dev/null | grep vm-; then
    echo -e "${GREEN}✓ VMs found as current user${NC}"
else
    echo -e "${RED}✗ No VMs found as current user${NC}"
fi
echo ""

# Test 3: VBoxManage with user detection logic (same as scripts)
echo -e "${YELLOW}Test 3: VM Detection with User Detection Logic${NC}"

# Detect VM user (same logic as in the scripts)
if [[ -n "$SUDO_USER" ]] && [[ "$SUDO_USER" != "root" ]]; then
    VM_USER="$SUDO_USER"
    echo "Detected VM_USER from SUDO_USER: $VM_USER"
else
    echo "Trying common usernames..."
    for user in fedora sekumar ubuntu ec2-user; do
        echo -n "  Checking $user... "
        if sudo -u "$user" VBoxManage list vms 2>/dev/null | grep -q "vm-"; then
            VM_USER="$user"
            echo -e "${GREEN}✓ Found VMs${NC}"
            break
        else
            echo "no VMs"
        fi
    done
fi

if [[ -n "$VM_USER" ]]; then
    echo -e "${GREEN}✓ VM_USER detected: $VM_USER${NC}"
else
    echo -e "${YELLOW}⚠ VM_USER not detected, will use current user${NC}"
fi
echo ""

# Test 4: Extract VM UUID
echo -e "${YELLOW}Test 4: Extract VM UUID${NC}"
if [[ -n "$VM_USER" ]]; then
    VMUUID=$(sudo -u "$VM_USER" VBoxManage list vms | grep vm- | awk -F '[{}]' '{ print $2 }' | head -n1)
else
    VMUUID=$(VBoxManage list vms | grep vm- | awk -F '[{}]' '{ print $2 }' | head -n1)
fi

if [[ -n "$VMUUID" ]]; then
    echo -e "${GREEN}✓ VM UUID: $VMUUID${NC}"
else
    echo -e "${RED}✗ Failed to extract VM UUID${NC}"
    exit 1
fi
echo ""

# Test 5: Get VM state
echo -e "${YELLOW}Test 5: Get VM State${NC}"
if [[ -n "$VM_USER" ]]; then
    VM_STATE=$(sudo -u "$VM_USER" VBoxManage showvminfo "vm-$VMUUID" --machinereadable 2>/dev/null | grep '^VMState=' | cut -d'"' -f2)
else
    VM_STATE=$(VBoxManage showvminfo "vm-$VMUUID" --machinereadable 2>/dev/null | grep '^VMState=' | cut -d'"' -f2)
fi

if [[ -n "$VM_STATE" ]]; then
    echo -e "${GREEN}✓ VM State: $VM_STATE${NC}"
else
    echo -e "${RED}✗ Failed to get VM state${NC}"
    exit 1
fi
echo ""

# Summary
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}All tests passed!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "Summary:"
echo "  VM Owner: ${VM_USER:-current user}"
echo "  VM UUID: $VMUUID"
echo "  VM State: $VM_STATE"
echo ""
echo -e "${GREEN}✓ The scripts should now work correctly with sudo${NC}"
