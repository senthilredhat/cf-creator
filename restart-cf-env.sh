#!/bin/bash

###############################################################################
# Cloud Foundry Environment Recovery Script
#
# Run this script after VM restart to restore the CF environment
# without full reinstallation.
#
# Usage: ./restart-cf-env.sh
###############################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠${NC} $*"
}

echo ""
log "=== Cloud Foundry Environment Recovery ==="
echo ""

# Step 1: Ensure VirtualBox kernel modules are loaded
log "Step 1: Checking VirtualBox kernel modules..."
if ! lsmod | grep -q vboxdrv; then
    log_warning "VirtualBox driver not loaded, reconfiguring..."
    sudo /sbin/vboxconfig
    log_success "VirtualBox reconfigured"
else
    log_success "VirtualBox driver already loaded"
fi

# Check VirtualBox service
if ! systemctl is-active --quiet vboxdrv.service; then
    log_warning "VirtualBox service not active, starting..."
    sudo systemctl start vboxdrv.service
fi
log_success "VirtualBox service is running"

# Step 2: Check if BOSH Director VM exists
log "Step 2: Checking BOSH Director VM..."
if ! VBoxManage list vms | grep -q "bosh"; then
    log_error "BOSH Director VM not found!"
    log_error "You may need to run: ./deploy-cf.sh from phase5_bosh_deployment"
    exit 1
fi

# Step 3: Start BOSH Director VM if not running
log "Step 3: Checking if BOSH Director is running..."
if ! VBoxManage list runningvms | grep -q "bosh"; then
    log_warning "BOSH Director VM is stopped, starting..."
    VM_NAME=$(VBoxManage list vms | grep bosh | awk -F'"' '{print $2}')
    VBoxManage startvm "$VM_NAME" --type headless
    log "Waiting 30 seconds for BOSH to start..."
    sleep 30
    log_success "BOSH Director VM started"
else
    log_success "BOSH Director VM already running"
fi

# Step 4: Restore network route
log "Step 4: Restoring network route to BOSH containers..."
if ip route | grep -q "10.244.0.0/16"; then
    log_warning "Route already exists, removing old route..."
    sudo ip route del 10.244.0.0/16 via 192.168.56.6 || true
fi
sudo ip route add 10.244.0.0/16 via 192.168.56.6
log_success "Network route restored"

# Step 5: Test connectivity
log "Step 5: Testing connectivity to BOSH Director..."
if ping -c 2 -W 5 192.168.56.6 > /dev/null 2>&1; then
    log_success "BOSH Director is reachable"
else
    log_error "Cannot reach BOSH Director at 192.168.56.6"
    log_error "Wait a bit longer and try again, or check VirtualBox VM status"
    exit 1
fi

# Step 6: Set environment variables
log "Step 6: Setting up environment variables..."
export PATH="$HOME/.local/bin:$PATH"
export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET=$(bosh int ~/deployments/vbox/creds.yml --path /admin_password)

# Step 7: Verify BOSH environment
log "Step 7: Verifying BOSH environment..."
if bosh -e vbox env; then
    log_success "BOSH environment is healthy"
else
    log_error "BOSH environment check failed"
    exit 1
fi

# Step 8: Check Cloud Foundry deployment status
log "Step 8: Checking Cloud Foundry deployment status..."
if bosh -e vbox -d cf vms --column=instance --column=process_state | grep -q "running"; then
    log_success "Cloud Foundry VMs are running"
else
    log_warning "Some Cloud Foundry VMs may not be running"
    log "Run: bosh -e vbox -d cf vms"
fi

echo ""
log_success "==================================================="
log_success "Environment recovery completed!"
log_success "==================================================="
echo ""

# Display helpful commands
cat << EOF
${GREEN}Environment variables set:${NC}
  export PATH="$HOME/.local/bin:\$PATH"
  export BOSH_CLIENT=admin
  export BOSH_CLIENT_SECRET=<from creds.yml>

${GREEN}Useful commands:${NC}
  bosh -e vbox env                    # Check BOSH status
  bosh -e vbox -d cf vms              # Check CF VMs
  cf login -a https://api.bosh-lite.com --skip-ssl-validation -u admin -p \$(credhub get -n /bosh-lite/cf/cf_admin_password -q)

${YELLOW}Note:${NC} The environment variables are only set in this shell session.
Add them to your ~/.bashrc for persistence:

  echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> ~/.bashrc

EOF
