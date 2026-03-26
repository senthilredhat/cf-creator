# Cloud Foundry Cleanup & Restart Guide

## Overview

When `cf-preserve.sh` and `cf-restore.sh` don't work 100%, use the cleanup script to reset your deployment and restart from a specific phase.

## Quick Reference

### Scenario 1: VirtualBox Networking Issues
**Problem:** VirtualBox NAT network or host-only interface is misconfigured or has lingering issues.

**Solution:**
```bash
./cf-cleanup.sh --from phase4
./deploy-cf.sh
```

**What this does:**
- Removes VirtualBox NAT network (NatNetwork)
- Removes host-only interface (vboxnet0)
- Removes BOSH Director VM
- Cleans up deployments/vbox directory
- Removes bosh-deployment and cf-deployment checkouts
- Removes IP route to BOSH containers
- Resets checkpoint to before phase4

**Restarts from:** `phase4_vbox_networking`

---

### Scenario 2: BOSH or CF Deployment Issues
**Problem:** BOSH deployment failed or CF deployment has issues, but VirtualBox networking is fine.

**Solution:**
```bash
./cf-cleanup.sh --from phase5
./deploy-cf.sh
```

**What this does:**
- **Keeps** VirtualBox networking intact (vboxnet0, NatNetwork)
- Removes BOSH Director VM
- Cleans up deployments/vbox directory
- Removes bosh-deployment and cf-deployment checkouts
- Removes IP route to BOSH containers
- Resets checkpoint to before phase5

**Restarts from:** `phase5_bosh_deployment`

---

### Scenario 3: Complete Reset
**Problem:** You want to start completely fresh.

**Solution:**
```bash
./cf-cleanup.sh --full
./deploy-cf.sh
```

**What this does:**
- Complete cleanup of all artifacts
- Removes VirtualBox networking
- Removes all deployments
- Removes all checkouts
- Resets all checkpoints

**Restarts from:** `phase1_kernel_setup`

---

## Cleanup Details

### VirtualBox Resources Cleaned
- NAT network: `NatNetwork` (10.0.2.0/24)
- Host-only interface: `vboxnet0` (192.168.56.1)
- BOSH Director VM (if exists)

### Directories Cleaned
- `~/deployments/vbox/` - BOSH state and credentials
- `~/workspace/bosh-deployment/` - BOSH deployment checkout
- `~/cf-deployment/` - CF deployment checkout

### Network Routes Cleaned
- IP route: `10.244.0.0/16 via 192.168.56.6`

### System Files Cleaned
- `/etc/hosts` entries for bosh-lite.com domains
- `~/credhub-ca.crt`
- `~/.cf-deployment-state` (checkpoint file)

---

## Usage Examples

### Example 1: cf-preserve/cf-restore failed
```bash
# You tried cf-preserve.sh but it didn't work 100%
# Now you want to restart from BOSH deployment

./cf-cleanup.sh --from phase5
# Confirm with: yes
./deploy-cf.sh
```

### Example 2: VirtualBox networking is broken
```bash
# You see errors about vboxnet0 or NatNetwork
# Clean everything and start from networking phase

./cf-cleanup.sh --from phase4
# Confirm with: yes
./deploy-cf.sh
```

### Example 3: Check what will be cleaned (dry run)
```bash
# View the help to understand what each option does
./cf-cleanup.sh --help
```

---

## Verification After Cleanup

### Check VirtualBox resources
```bash
# Should show nothing (or only non-BOSH VMs)
VBoxManage list vms
VBoxManage list hostonlyifs
VBoxManage list natnetworks
```

### Check deployment status
```bash
# Should show incomplete phases after the cleanup point
./deploy-cf.sh status
```

### Check directories
```bash
# Should not exist after cleanup
ls ~/deployments/vbox/
ls ~/workspace/bosh-deployment/
ls ~/cf-deployment/
```

---

## Common Issues

### Issue: "Could not remove vboxnet0"
**Solution:** VirtualBox might be using it. Try:
```bash
# Force kill any VBox processes
VBoxManage list runningvms
VBoxManage controlvm <vm-name> poweroff
# Then run cleanup again
./cf-cleanup.sh --from phase4
```

### Issue: "Could not delete BOSH Director"
**Solution:** Force removal:
```bash
# Find the VM
VBoxManage list vms | grep -i bosh
# Force power off and delete
VBoxManage controlvm "vm-name" poweroff
VBoxManage unregistervm "vm-name" --delete
# Then run cleanup again
./cf-cleanup.sh --from phase5
```

### Issue: Cleanup says "yes" but I typed "yes"
**Solution:** The script requires exactly "yes" (lowercase). Not "Yes", "YES", or "y".

---

## Phases Reference

1. **phase1_kernel_setup** - Kernel locking and setup
2. **phase2_kvm_management** - KVM module blacklisting
3. **phase3_dependencies** - Install BOSH, CF CLI, VirtualBox
4. **phase4_vbox_networking** - Configure VBox networking ← Cleanup option
5. **phase5_bosh_deployment** - Deploy BOSH Director ← Cleanup option
6. **phase6_cf_deployment** - Deploy Cloud Foundry
7. **phase7_cf_config** - Configure and login to CF

---

## Safety Features

- **Confirmation required:** All cleanup operations require typing "yes" to proceed
- **Logging:** All actions are logged to `cf-deployment.log`
- **Selective cleanup:** Choose what to clean (networking, BOSH, CF)
- **Checkpoint reset:** State file is properly updated for correct resume

---

## Tips

1. **Start with phase5 cleanup:** If you're unsure, try `--from phase5` first. It's less destructive and keeps networking.

2. **Check logs:** Always check `cf-deployment.log` if something goes wrong.

3. **Verify before restart:** Run `./deploy-cf.sh status` after cleanup to verify the state.

4. **Preserve important data:** If you have any custom changes in the checkout directories, back them up before cleanup.

5. **Network issues = phase4:** Any VirtualBox networking issues should use `--from phase4`.

---

## Script Location

- Cleanup script: `./cf-cleanup.sh`
- Deployment script: `./deploy-cf.sh`
- Log file: `./cf-deployment.log`
- State file: `~/.cf-deployment-state`
