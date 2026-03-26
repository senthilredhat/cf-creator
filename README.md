# Cloud Foundry Deployment Script

Automated deployment script for Cloud Foundry on Fedora VM with checkpoint/resume capability.

## Overview

This script automates the deployment process from the [Konveyor asset-generation documentation](https://github.com/konveyor/asset-generation/blob/main/docs/deploying-cf-locally.md) with enhancements for:

- **Error Handling**: Stops immediately when issues occur
- **Checkpoint System**: Resume from where you left off after fixing issues
- **Manual Intervention**: Pauses for steps requiring human input
- **Logging**: Detailed logs of all operations
- **Idempotency**: Skip already-completed phases

## Prerequisites

- Fedora VM with root/sudo access
- Internet connectivity
- Sufficient resources (16GB RAM, 16 CPUs recommended)
- Hardware virtualization support (VT-x/AMD-V)
- If you are using EC2 Use
   - AMID: ami-0007a783d3ea2b227
   - Name: "Fedora-Cloud-42.20250825.0 (x86_64) for HVM Instances"
   - M8i.4xlarge instance

## Quick Start

1. **Make the script executable:**
   ```bash
   chmod +x deploy-cf.sh
   ```

2. **Run the deployment:**
   ```bash
   ./deploy-cf.sh
   ```

3. **If the script stops due to an error:**
   - Fix the issue
   - Simply run `./deploy-cf.sh` again - it will resume from where it stopped

## Commands

```bash
./deploy-cf.sh              # Start or resume deployment
./deploy-cf.sh status       # Show current progress
./deploy-cf.sh reset        # Reset all checkpoints and start over
./deploy-cf.sh from PHASE   # Resume from specific phase
./deploy-cf.sh help         # Show help message
```

## Deployment Phases

The script executes the following phases in order:

### Phase 1: Kernel Setup and Locking
- Downloads and installs specific kernel version (6.15.10)
- Locks kernel packages to prevent updates

### Phase 2: KVM Module Management
- Unloads KVM modules
- Blacklists KVM to allow VirtualBox to work properly

### Phase 3: Dependencies Installation
- Installs Cloud Foundry CLI
- Installs BOSH CLI
- Installs VirtualBox and configures kernel modules

### Phase 4: VirtualBox Network Configuration
- Clones bosh-deployment repository
- Configures BOSH deployment files
- **MANUAL STEP**: Pauses to allow you to review/edit configuration files
- Sets up VirtualBox NAT and host-only networks

### Phase 5: BOSH Director Deployment
- Deploys BOSH Director VM
- Configures BOSH environment
- Sets up networking routes
- Updates DNS runtime config

### Phase 6: Cloud Foundry Deployment
- Clones cf-deployment repository
- Deploys Cloud Foundry platform (this takes a while!)

### Phase 7: CF Configuration and Login
- Adds host entries for CF domains
- Installs and configures CredHub CLI
- Logs into Cloud Foundry

## Manual Intervention Steps

The script will pause during **Phase 4** to allow you to review these configuration files:

1. `~/workspace/bosh-deployment/virtualbox/cpi.yml`
   - CPU and memory settings (default: 16 CPUs, 16GB RAM)

2. `~/workspace/bosh-deployment/virtualbox/outbound-network.yml`
   - DNS configuration (default: 8.8.8.8)

**How to handle the pause:**
1. The script displays the file paths
2. Open the files in another terminal if you want to make changes
3. Press ENTER in the script terminal when ready to continue

## State Management

The script uses two files to track progress:

- **State File**: `~/.cf-deployment-state`
  - Tracks completed phases
  - Allows resume capability

- **Log File**: `cf-deployment.log` (in current directory)
  - Detailed logs with timestamps
  - Review for troubleshooting

## Common Workflows

### Checking Progress
```bash
./deploy-cf.sh status
```

Output example:
```
=== Cloud Foundry Deployment Status ===

✓ phase1_kernel_setup
✓ phase2_kvm_management
✓ phase3_dependencies
○ phase4_vbox_networking
○ phase5_bosh_deployment
○ phase6_cf_deployment
○ phase7_cf_config
```

### Recovering from Errors

1. **Review the error** in the terminal or log file
2. **Fix the underlying issue** (e.g., network, permissions, disk space)
3. **Resume the deployment:**
   ```bash
   ./deploy-cf.sh
   ```

The script automatically resumes from the last incomplete phase.

### Restarting from Specific Phase

If you need to re-run a specific phase:

```bash
./deploy-cf.sh from phase5_bosh_deployment
```

This will:
- Clear the checkpoint for the specified phase and all subsequent phases
- Resume execution from that phase

### Starting Over Completely

```bash
./deploy-cf.sh reset
./deploy-cf.sh
```

## After Successful Deployment

Once the script completes successfully, you'll have:

- Cloud Foundry running at `https://api.bosh-lite.com`
- Admin credentials:
  - Username: `admin`
  - Password: Retrieved from CredHub
- Already logged in and ready to use

### Verify the deployment:

```bash
cf target
cf apps
cf create-org test-org
cf create-space test-space -o test-org
cf target -o test-org -s test-space
```

## Environment Variables Set

The script sets up these environment variables (you may need to export them in new shells):

```bash
export PATH="$HOME/.local/bin:$PATH"
export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET=$(bosh int ~/deployments/vbox/creds.yml --path /admin_password)
export CREDHUB_SERVER=https://192.168.56.6:8844
export CREDHUB_CLIENT=credhub-admin
export CREDHUB_SECRET=$(bosh int ~/deployments/vbox/creds.yml --path /credhub_admin_client_secret)
export CREDHUB_CA_CERT="$HOME/credhub-ca.crt"
```

## Troubleshooting

### Script stops at Phase 3 (VirtualBox installation)

**Issue**: VirtualBox kernel module compilation fails

**Solution**:
```bash
sudo dnf install -y kernel-devel-$(uname -r)
sudo /sbin/vboxconfig
./deploy-cf.sh
```

### Script stops at Phase 5 (BOSH deployment)

**Issue**: BOSH create-env fails (the script retries 5 times automatically)

**Solution**:
- Check VirtualBox networking: `VBoxManage list natnetworks`
- Check available resources: `free -h` and `nproc`
- Review logs in `cf-deployment.log`
- Resume with `./deploy-cf.sh`

### Network connectivity issues

**Issue**: Cannot reach CF API after deployment

**Solution**:
```bash
# Verify route exists
ip route | grep 10.244.0.0

# Re-add if missing
sudo ip route add 10.244.0.0/16 via 192.168.56.6

# Verify hosts entries
grep bosh-lite.com /etc/hosts

# Test connectivity
ping -c3 192.168.56.6
```

### Manual phase re-execution

If a specific command in a phase failed and you fixed it manually:

```bash
# Mark the phase as complete manually if you executed steps by hand
echo "phase3_dependencies" >> ~/.cf-deployment-state

# Or re-run from that phase
./deploy-cf.sh from phase3_dependencies
```

## File Locations

```
~/workspace/bosh-deployment/          # BOSH deployment files
~/deployments/vbox/                   # BOSH director deployment
  ├── state.json                      # BOSH director state
  └── creds.yml                       # BOSH credentials
~/cf-deployment/                      # Cloud Foundry deployment files
~/.local/bin/                         # CLI tools (bosh, credhub)
~/.cf-deployment-state                # Script checkpoint state
./cf-deployment.log                   # Deployment logs
```

## System Requirements

- **OS**: Fedora (tested on Fedora 40-43)
- **Kernel**: 6.15.10-200.fc42.x86_64 (locked by script)
- **RAM**: 16GB minimum (allocated to BOSH Director)
- **CPU**: 16 cores recommended
- **Disk**: 100GB+ free space
- **Network**: Internet access for package downloads

## Important Notes

1. **Kernel Version Lock**: The script locks the kernel to version 6.15.10 to ensure compatibility
2. **KVM Disabled**: KVM is blacklisted to allow VirtualBox to function properly
3. **VirtualBox Version**: Uses VirtualBox 7.2.4 specifically
4. **Long Running**: Phase 6 (CF deployment) can take 30-60 minutes or more
5. **Sudo Required**: Many operations require sudo access - you may be prompted for password
6. **Manual Review**: Phase 4 pauses for you to review configuration files

## Support

For issues related to:
- **This script**: Check `cf-deployment.log` and try resuming with `./deploy-cf.sh`
- **BOSH/CF deployment**: Refer to [Konveyor documentation](https://github.com/konveyor/asset-generation/blob/main/docs/deploying-cf-locally.md)
- **Cloud Foundry**: See [CF documentation](https://docs.cloudfoundry.org/)

## License

This script is provided as-is for use with Cloud Foundry deployment on Fedora systems.
