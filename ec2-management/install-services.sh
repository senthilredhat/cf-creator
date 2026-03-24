#!/bin/bash

###############################################################################
# Cloud Foundry EC2 Management Services Installer
#
# This script installs and enables the systemd services that automatically
# preserve and restore Cloud Foundry VM state on EC2 shutdown/startup.
#
# Usage:
#   sudo ./install-services.sh
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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_DIR="/etc/systemd/system"

log "========================================="
log "Cloud Foundry EC2 Management Installer"
log "========================================="
echo ""

# Check prerequisites
log "Checking prerequisites..."

if ! command -v VBoxManage &> /dev/null; then
    log_error "VirtualBox is not installed"
    log "Please install VirtualBox first"
    exit 1
fi
log_success "VirtualBox found"

if ! command -v xmlstarlet &> /dev/null; then
    log_warning "xmlstarlet is not installed"
    log "Installing xmlstarlet..."
    dnf install -y xmlstarlet
    log_success "xmlstarlet installed"
else
    log_success "xmlstarlet found"
fi

echo ""
log "Installing scripts and services..."

# Make scripts executable
chmod +x "$SCRIPT_DIR/cf-preserve.sh"
chmod +x "$SCRIPT_DIR/cf-restore.sh"
log_success "Scripts made executable"

# Copy scripts to /usr/local/bin/
cp "$SCRIPT_DIR/cf-preserve.sh" /usr/local/bin/cf-preserve.sh
cp "$SCRIPT_DIR/cf-restore.sh" /usr/local/bin/cf-restore.sh
chmod +x /usr/local/bin/cf-preserve.sh
chmod +x /usr/local/bin/cf-restore.sh
log_success "Scripts copied to /usr/local/bin/"

# Create state directory (relative to script location)
mkdir -p "$SCRIPT_DIR/.state"

# Get the actual user (not root) if run with sudo
ACTUAL_USER="${SUDO_USER:-$USER}"
if [[ "$ACTUAL_USER" != "root" ]] && id "$ACTUAL_USER" &>/dev/null; then
    chown -R "$ACTUAL_USER":"$ACTUAL_USER" "$SCRIPT_DIR/.state"
fi
log_success "State directory created at $SCRIPT_DIR/.state"

# Update service files to use /usr/local/bin and copy to systemd directory
sed "s|/home/sekumar/pcf2ocp/cf-creator/ec2-management/cf-preserve.sh|/usr/local/bin/cf-preserve.sh|g; s|/home/sekumar/pcf2ocp/cf-creator/ec2-management|$SCRIPT_DIR|g" \
    "$SCRIPT_DIR/cf-preserve.service" > "$SYSTEMD_DIR/cf-preserve.service"
sed "s|/home/sekumar/pcf2ocp/cf-creator/ec2-management/cf-restore.sh|/usr/local/bin/cf-restore.sh|g; s|/home/sekumar/pcf2ocp/cf-creator/ec2-management|$SCRIPT_DIR|g" \
    "$SCRIPT_DIR/cf-restore.service" > "$SYSTEMD_DIR/cf-restore.service"
log_success "Service files copied to $SYSTEMD_DIR with updated paths"

# Reload systemd
systemctl daemon-reload
log_success "Systemd daemon reloaded"

# Enable services
systemctl enable cf-preserve.service
systemctl enable cf-restore.service
log_success "Services enabled"

# Create log files with proper permissions
touch /var/log/cf-preserve.log
touch /var/log/cf-restore.log
touch /var/log/cf-shutdown-notifications.log
touch /var/log/cf-startup-notifications.log
chmod 644 /var/log/cf-*.log
log_success "Log files created"

echo ""
log "========================================="
log_success "Installation completed successfully!"
log "========================================="
echo ""

log "The following services are now active:"
echo "  • cf-preserve.service - Saves VM state before shutdown"
echo "  • cf-restore.service  - Restores VM state on startup"
echo ""

log "Log files:"
echo "  • /var/log/cf-preserve.log - Preservation logs"
echo "  • /var/log/cf-restore.log - Restoration logs"
echo "  • /var/log/cf-shutdown-notifications.log - Shutdown notifications"
echo "  • /var/log/cf-startup-notifications.log - Startup notifications"
echo ""

log "You can also view logs with:"
echo "  sudo journalctl -u cf-preserve.service"
echo "  sudo journalctl -u cf-restore.service"
echo ""

log "Status commands:"
echo "  sudo systemctl status cf-preserve.service"
echo "  sudo systemctl status cf-restore.service"
echo ""

log "To test the services without rebooting:"
echo "  sudo systemctl start cf-preserve.service  # Saves VM state"
echo "  sudo systemctl start cf-restore.service   # Restores VM state"
echo ""

log_success "Setup complete! Your Cloud Foundry VM will now be automatically"
log_success "preserved on shutdown and restored on startup."
echo ""

# Check if a VM exists
# Check for both root and actual user VMs
VM_FOUND=false
if VBoxManage list vms 2>/dev/null | grep -q "vm-"; then
    VM_FOUND=true
elif [[ -n "$ACTUAL_USER" ]] && sudo -u "$ACTUAL_USER" VBoxManage list vms 2>/dev/null | grep -q "vm-"; then
    VM_FOUND=true
fi

if [[ "$VM_FOUND" == "true" ]]; then
    log_success "VirtualBox VM detected and ready for management"
else
    log_warning "No VirtualBox VM found yet. Services will activate after CF deployment."
fi
