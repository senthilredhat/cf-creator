#!/bin/bash

###############################################################################
# Cloud Foundry Deployment Script for Fedora
#
# This script automates the deployment of Cloud Foundry on a Fedora VM
# with checkpoint/resume capability and error handling.
#
# Usage:
#   ./deploy-cf.sh              # Start or resume deployment
#   ./deploy-cf.sh status       # Show current progress
#   ./deploy-cf.sh reset        # Reset all checkpoints and start over
#   ./deploy-cf.sh from PHASE   # Resume from specific phase
###############################################################################

set -e  # Exit on any error
set -o pipefail  # Catch errors in pipes

# Configuration
STATE_FILE="$HOME/.cf-deployment-state"
LOG_FILE="$PWD/cf-deployment.log"
WORKSPACE_DIR="$HOME/workspace"
DEPLOYMENTS_DIR="$HOME/deployments/vbox"

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

# Save checkpoint
checkpoint() {
    local phase=$1
    echo "$phase" >> "$STATE_FILE"
    log_success "Checkpoint: $phase completed"
}

# Check if phase is already completed
is_completed() {
    local phase=$1
    if [[ -f "$STATE_FILE" ]] && grep -q "^$phase$" "$STATE_FILE"; then
        return 0  # true
    else
        return 1  # false
    fi
}

# Pause for manual intervention
pause_for_manual() {
    local message=$1
    log_warning "MANUAL INTERVENTION REQUIRED"
    echo -e "${YELLOW}$message${NC}"
    echo -e "${YELLOW}Press ENTER when you have completed this step...${NC}"
    read -r
}

# Show status
show_status() {
    echo -e "${BLUE}=== Cloud Foundry Deployment Status ===${NC}"
    echo ""

    local phases=(
        "phase1_kernel_setup"
        "phase2_kvm_management"
        "phase3_dependencies"
        "phase4_vbox_networking"
        "phase5_bosh_deployment"
        "phase6_cf_deployment"
        "phase7_cf_config"
    )

    for phase in "${phases[@]}"; do
        if is_completed "$phase"; then
            echo -e "${GREEN}✓${NC} $phase"
        else
            echo -e "${YELLOW}○${NC} $phase"
        fi
    done
    echo ""
}

# Reset all checkpoints
reset_state() {
    log_warning "Resetting all checkpoints..."
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        log_success "State file removed"
    fi
    log_success "Reset complete. Run ./deploy-cf.sh to start from beginning"
}

###############################################################################
# Phase Functions
###############################################################################

phase1_kernel_setup() {
    local phase="phase1_kernel_setup"
    if is_completed "$phase"; then
        log "Skipping $phase (already completed)"
        return 0
    fi

    log "=== Phase 1: Kernel Setup and Locking ==="

    log "Detecting default kernel version..."
    KERNEL_PATH=$(sudo grubby --default-kernel)
    log "Default kernel: $KERNEL_PATH"

    # Extract version from path like /boot/vmlinuz-6.14.0-63.fc42.x86_64
    KERNEL_VERSION=$(basename "$KERNEL_PATH" | sed 's/vmlinuz-//')
    KERNEL_VERSION_SHORT="${KERNEL_VERSION%.x86_64}"

    # Parse version components
    KERNEL_VER=$(echo "$KERNEL_VERSION_SHORT" | cut -d'-' -f1)   # e.g., 6.14.0
    KERNEL_REL=$(echo "$KERNEL_VERSION_SHORT" | cut -d'-' -f2)   # e.g., 63
    KERNEL_DIST=$(echo "$KERNEL_VERSION_SHORT" | cut -d'-' -f3)  # e.g., fc42

    log "Kernel version: $KERNEL_VER"
    log "Kernel release: $KERNEL_REL"
    log "Kernel distribution: $KERNEL_DIST"
    log "Full version string: $KERNEL_VERSION_SHORT"

    log "Installing wget..."
    sudo dnf install -y wget

    log "Downloading kernel-devel package..."
    wget "https://kojipkgs.fedoraproject.org/packages/kernel/${KERNEL_VER}/${KERNEL_REL}.${KERNEL_DIST}/x86_64/kernel-devel-${KERNEL_VERSION_SHORT}.x86_64.rpm"

    log "Installing kernel-devel..."
    sudo dnf install -y "kernel-devel-${KERNEL_VERSION_SHORT}.x86_64.rpm"

    log "Adding kernel version locks..."
    sudo dnf versionlock add "kernel-core-${KERNEL_VERSION_SHORT}.x86_64"
    sudo dnf versionlock add "kernel-modules-core-${KERNEL_VERSION_SHORT}.x86_64"
    sudo dnf versionlock add "kernel-devel-${KERNEL_VERSION_SHORT}.x86_64"
    sudo dnf versionlock add 'kernel*'

    checkpoint "$phase"
    log_success "Phase 1 completed successfully"
}

phase2_kvm_management() {
    local phase="phase2_kvm_management"
    if is_completed "$phase"; then
        log "Skipping $phase (already completed)"
        return 0
    fi

    log "=== Phase 2: KVM Module Management ==="

    echo '-----------------------------------------------------------------'

    log "Unloading KVM modules if loaded..."
    if lsmod | grep -q kvm_intel; then
        sudo rmmod kvm_intel
        log "Unloaded kvm_intel"
    fi

    if lsmod | grep -q kvm_amd; then
        sudo rmmod kvm_amd
        log "Unloaded kvm_amd"
    fi

    if lsmod | grep -q kvm; then
        sudo rmmod kvm
        log "Unloaded kvm"
    fi

    log "Creating KVM blacklist configuration..."
    sudo bash -c 'cat << EOF > /etc/modprobe.d/kvm-blacklist.conf
blacklist kvm
blacklist kvm_amd
blacklist kvm_intel
EOF'

    log "Updating grub configuration (adding then removing kvm parameter)..."
    sudo grubby --update-kernel=ALL --args="kvm.enable_virt_at_load=0"
    sudo grubby --update-kernel=ALL --remove-args="kvm.enable_virt_at_load=0"

    checkpoint "$phase"
    log_success "Phase 2 completed successfully"
}

phase3_dependencies() {
    local phase="phase3_dependencies"
    if is_completed "$phase"; then
        log "Skipping $phase (already completed)"
        return 0
    fi

    log "=== Phase 3: Dependencies Installation ==="

    log "Adding Cloud Foundry CLI repository..."
    sudo wget -O /etc/yum.repos.d/cloudfoundry-cli.repo https://packages.cloudfoundry.org/fedora/cloudfoundry-cli.repo

    log "Installing system dependencies..."
    sudo dnf install -y gcc make perl kernel-devel kernel-headers bzip2 git jq ruby wget yq cf8-cli

    log "Downloading BOSH CLI..."
    wget https://github.com/cloudfoundry/bosh-cli/releases/download/v7.9.8/bosh-cli-7.9.8-linux-amd64

    log "Installing BOSH CLI..."
    chmod +x ./bosh-cli-7.9.8-linux-amd64
    mkdir -p ~/.local/bin
    mv ./bosh-cli-7.9.8-linux-amd64 ~/.local/bin/bosh

    log "Verifying BOSH installation..."
    export PATH="$HOME/.local/bin:$PATH"
    bosh -v

    log "Downloading VirtualBox..."
    wget https://download.virtualbox.org/virtualbox/7.2.4/VirtualBox-7.2-7.2.4_170995_fedora40-1.x86_64.rpm

    log "Installing VirtualBox..."
    sudo dnf install -y VirtualBox-7.2-7.2.4_170995_fedora40-1.x86_64.rpm

    log "Configuring VirtualBox kernel modules..."
    sudo /sbin/vboxconfig

    log "Checking VirtualBox driver status..."
    systemctl status vboxdrv.service --no-pager || true

    log "Verifying VirtualBox installation..."
    VBoxManage list hostinfo

    checkpoint "$phase"
    log_success "Phase 3 completed successfully"
}

phase4_vbox_networking() {
    local phase="phase4_vbox_networking"
    if is_completed "$phase"; then
        log "Skipping $phase (already completed)"
        return 0
    fi

    log "=== Phase 4: VirtualBox Network Configuration ==="

    log "Cloning bosh-deployment repository..."
    git clone https://github.com/cloudfoundry/bosh-deployment "$WORKSPACE_DIR/bosh-deployment"

    log "Resetting to specific commit..."
    pushd "$WORKSPACE_DIR/bosh-deployment"
    git reset --hard 4e030b34f3ea6dae68262346c2c45dbd55f02499
    popd

    log "Creating deployments directory..."
    mkdir -p "$DEPLOYMENTS_DIR"

    log "Configuring DNS in outbound-network.yml..."
    yq e '.[0].value.dns=[ "8.8.8.8" ]' -i "$WORKSPACE_DIR/bosh-deployment/virtualbox/outbound-network.yml"

    log "Configuring CPU and memory in cpi.yml..."
    yq e '.[2].value.cpus=16' -i "$WORKSPACE_DIR/bosh-deployment/virtualbox/cpi.yml"
    yq e '.[2].value.memory=16384' -i "$WORKSPACE_DIR/bosh-deployment/virtualbox/cpi.yml"

    log_warning "Manual configuration files review required..."
    pause_for_manual "Please review and edit if needed:\n  1. $WORKSPACE_DIR/bosh-deployment/virtualbox/cpi.yml\n  2. $WORKSPACE_DIR/bosh-deployment/virtualbox/outbound-network.yml\n\nYou can edit these files now in another terminal."

    log "Creating VirtualBox NAT network..."
    sudo vboxmanage natnetwork add --netname NatNetwork --network 10.0.2.0/24 --dhcp on || log_warning "NAT network may already exist"

    log "Listing NAT networks..."
    sudo vboxmanage list natnetworks

    log "Creating host-only network interface..."
    sudo vboxmanage hostonlyif create

    log "Configuring host-only interface vboxnet0..."
    sudo vboxmanage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0

    checkpoint "$phase"
    log_success "Phase 4 completed successfully"
}

phase5_bosh_deployment() {
    local phase="phase5_bosh_deployment"
    if is_completed "$phase"; then
        log "Skipping $phase (already completed)"
        return 0
    fi

    log "=== Phase 5: BOSH Director Deployment ==="

    cd "$DEPLOYMENTS_DIR"

    echo '--------------Creating BOSH Director VM--------------------'

    log "Deploying BOSH Director (with retry logic)..."
    export PATH="$HOME/.local/bin:$PATH"

    for i in {1..5}; do
        log "Attempt $i of 5..."
        if bosh create-env "$WORKSPACE_DIR/bosh-deployment/bosh.yml" \
          --state ./state.json \
          -o "$WORKSPACE_DIR/bosh-deployment/virtualbox/cpi.yml" \
          -o "$WORKSPACE_DIR/bosh-deployment/virtualbox/outbound-network.yml" \
          -o "$WORKSPACE_DIR/bosh-deployment/bosh-lite.yml" \
          -o "$WORKSPACE_DIR/bosh-deployment/bosh-lite-runc.yml" \
          -o "$WORKSPACE_DIR/bosh-deployment/uaa.yml" \
          -o "$WORKSPACE_DIR/bosh-deployment/credhub.yml" \
          -o "$WORKSPACE_DIR/bosh-deployment/jumpbox-user.yml" \
          --vars-store ./creds.yml \
          -v director_name=bosh-lite \
          -v internal_ip=192.168.56.6 \
          -v internal_gw=192.168.56.1 \
          -v internal_cidr=192.168.56.0/24 \
          -v outbound_network_name=NatNetwork; then
            log_success "BOSH Director deployed successfully"
            break
        else
            log_warning "BOSH deployment attempt $i failed, retrying..."
        fi
    done

    log "Listing VirtualBox VMs..."
    VBoxManage list vms

    log "Setting up BOSH environment..."
    export BOSH_CLIENT=admin
    export BOSH_CLIENT_SECRET=$(bosh int ./creds.yml --path /admin_password)

    log "Creating BOSH alias..."
    bosh alias-env vbox -e 192.168.56.6 --ca-cert <(bosh int ./creds.yml --path /director_ssl/ca)

    log "Adding route to BOSH containers network..."
    sudo ip route add 10.244.0.0/16 via 192.168.56.6 || log_warning "Route may already exist"

    log "Testing connectivity to BOSH Director..."
    ping -c3 192.168.56.6

    log "Verifying BOSH environment..."
    bosh -e vbox env

    log "Updating DNS runtime config..."
    bosh -e vbox update-runtime-config "$WORKSPACE_DIR/bosh-deployment/runtime-configs/dns.yml" --name dns

    checkpoint "$phase"
    log_success "Phase 5 completed successfully"
}

phase6_cf_deployment() {
    local phase="phase6_cf_deployment"
    if is_completed "$phase"; then
        log "Skipping $phase (already completed)"
        return 0
    fi

    log "=== Phase 6: Cloud Foundry Deployment ==="

    export PATH="$HOME/.local/bin:$PATH"
    export BOSH_CLIENT=admin
    export BOSH_CLIENT_SECRET=$(bosh int "$DEPLOYMENTS_DIR/creds.yml" --path /admin_password)

    log "Cloning cf-deployment repository..."
    git clone https://github.com/cloudfoundry/cf-deployment.git "$HOME/cf-deployment"

    cd "$HOME/cf-deployment"

    log "Checking out specific version..."
    git reset --hard v51.2.0

    log "Fetching stemcell version..."
    export STEMCELL_VERSION=$(curl -s "https://bosh.io/api/v1/stemcells/bosh-warden-boshlite-ubuntu-jammy-go_agent" | jq -r '.[0].version')

    log "Fetching stemcell SHA1..."
    export STEMCELL_SHA1=$(curl -s "https://bosh.io/api/v1/stemcells/bosh-warden-boshlite-ubuntu-jammy-go_agent" | jq -r --arg version "$STEMCELL_VERSION" '.[] | select(.version == $version) | .regular.sha1')

    log "Stemcell version: $STEMCELL_VERSION"
    log "Stemcell SHA1: $STEMCELL_SHA1"

    log "Updating cloud config..."
    bosh -e vbox update-cloud-config "$HOME/cf-deployment/iaas-support/bosh-lite/cloud-config.yml"

    log "Updating cf-deployment.yml with stemcell information..."
    yq e '.stemcells[0].alias = "default" | .stemcells[0].os = "ubuntu-jammy" | .stemcells[0].version = env(STEMCELL_VERSION)' -i cf-deployment.yml

    log "Uploading stemcell to BOSH..."
    bosh -e vbox upload-stemcell \
      --sha1 "$STEMCELL_SHA1" \
      "https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-jammy-go_agent?v=${STEMCELL_VERSION}"

    log "Deploying Cloud Foundry (this will take a while)..."
    bosh -n -e vbox -d cf deploy \
      cf-deployment.yml \
      -o operations/bosh-lite.yml \
      -o operations/use-compiled-releases.yml \
      -v system_domain=bosh-lite.com \
      -v stemcell_os=ubuntu-jammy \
      -v stemcell_version="${STEMCELL_VERSION}"

    checkpoint "$phase"
    log_success "Phase 6 completed successfully"
}

phase7_cf_config() {
    local phase="phase7_cf_config"
    if is_completed "$phase"; then
        log "Skipping $phase (already completed)"
        return 0
    fi

    log "=== Phase 7: Cloud Foundry Configuration and Login ==="

    export PATH="$HOME/.local/bin:$PATH"

    log "Adding CF hosts entries..."
    sudo bash -c 'cat << EOF >> /etc/hosts
10.244.0.34 bosh-lite.com
10.244.0.34 api.bosh-lite.com
10.244.0.34 log-cache.bosh-lite.com
10.244.0.34 login.bosh-lite.com
10.244.0.34 uaa.bosh-lite.com
EOF'

    log "Configuring CF API endpoint..."
    cf api https://api.bosh-lite.com --skip-ssl-validation

    log "Downloading CredHub CLI..."
    cd "$HOME"
    wget https://github.com/cloudfoundry/credhub-cli/releases/download/2.9.48/credhub-linux-amd64-2.9.48.tgz

    log "Installing CredHub CLI..."
    tar zxvf credhub-linux-amd64-2.9.48.tgz
    mkdir -p ~/.local/bin
    mv credhub ~/.local/bin/

    log "Configuring CredHub environment..."
    export CREDHUB_SERVER=https://192.168.56.6:8844
    export CREDHUB_CLIENT=credhub-admin
    export CREDHUB_SECRET=$(bosh int "$DEPLOYMENTS_DIR/creds.yml" --path /credhub_admin_client_secret)

    log "Extracting CredHub CA certificate..."
    bosh int "$DEPLOYMENTS_DIR/creds.yml" --path /credhub_tls/ca > "$HOME/credhub-ca.crt"
    export CREDHUB_CA_CERT="$HOME/credhub-ca.crt"

    log "Connecting to CredHub..."
    credhub api "$CREDHUB_SERVER" --ca-cert="$CREDHUB_CA_CERT" --skip-tls-validation

    log "Verifying CredHub access..."
    credhub find

    log "Retrieving CF admin password..."
    CF_ADMIN_PASSWORD=$(credhub get -n /bosh-lite/cf/cf_admin_password -q)

    log "Logging into Cloud Foundry..."
    cf login -a https://api.bosh-lite.com --skip-ssl-validation -u admin -p "$CF_ADMIN_PASSWORD"

    checkpoint "$phase"
    log_success "Phase 7 completed successfully"

    echo ""
    log_success "==================================================="
    log_success "Cloud Foundry deployment completed successfully!"
    log_success "==================================================="
    echo ""
    log "CF API: https://api.bosh-lite.com"
    log "Username: admin"
    log "Password stored in CredHub: /bosh-lite/cf/cf_admin_password"
    echo ""
    log "You are now logged in and ready to use Cloud Foundry!"
}

###############################################################################
# Main Script Logic
###############################################################################

main() {
    # Ensure ~/.local/bin is in PATH
    export PATH="$HOME/.local/bin:$PATH"

    case "${1:-}" in
        status)
            show_status
            exit 0
            ;;
        reset)
            reset_state
            exit 0
            ;;
        from)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 from PHASE_NAME"
                exit 1
            fi
            log "Resuming from phase: $2"
            # Remove all checkpoints from this phase onward
            if [[ -f "$STATE_FILE" ]]; then
                sed -i "/^$2$/,\$d" "$STATE_FILE"
            fi
            ;;
        help|--help|-h)
            echo "Usage: $0 [COMMAND]"
            echo ""
            echo "Commands:"
            echo "  (none)         Start or resume deployment"
            echo "  status         Show deployment progress"
            echo "  reset          Reset all checkpoints and start over"
            echo "  from PHASE     Resume from specific phase"
            echo "  help           Show this help message"
            echo ""
            echo "Phases:"
            echo "  phase1_kernel_setup"
            echo "  phase2_kvm_management"
            echo "  phase3_dependencies"
            echo "  phase4_vbox_networking"
            echo "  phase5_bosh_deployment"
            echo "  phase6_cf_deployment"
            echo "  phase7_cf_config"
            exit 0
            ;;
    esac

    log "Starting Cloud Foundry deployment..."
    log "Log file: $LOG_FILE"
    log "State file: $STATE_FILE"
    echo ""

    # Execute phases in order
    phase1_kernel_setup
    phase2_kvm_management
    phase3_dependencies
    phase4_vbox_networking
    phase5_bosh_deployment
    phase6_cf_deployment
    phase7_cf_config

    log_success "All phases completed successfully!"
}

# Error handler
error_handler() {
    log_error "An error occurred on line $1"
    log_error "Deployment stopped. Fix the issue and run './deploy-cf.sh' to resume."
    exit 1
}

trap 'error_handler $LINENO' ERR

# Run main function
main "$@"
