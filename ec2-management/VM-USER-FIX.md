# VirtualBox VM User Detection Fix

## Problem

When running `cf-preserve.sh` or `cf-restore.sh` as root (with `sudo`), the scripts couldn't detect VirtualBox VMs because:

1. VirtualBox stores VM information **per user**
2. When running as `root`, VBoxManage looks for VMs in `/root/.config/VirtualBox/`
3. Your VMs are stored in `/home/fedora/.config/VirtualBox/` (or similar)
4. Result: Script thinks no VMs exist even though they do

### Example of the Issue

```bash
# As your user (fedora)
$ VBoxManage list vms | grep vm-
"vm-ce534bb8-e033-4911-6ff0-1b7a2c1e675a" {ce534bb8-e033-4911-6ff0-1b7a2c1e675a}
# ✓ Works! VM found

# As root
$ sudo VBoxManage list vms | grep vm-
# ✗ No output! Root can't see user's VMs
```

## Solution

Updated all scripts to:
1. **Detect the actual VM owner** using `$SUDO_USER` environment variable
2. **Run VBoxManage commands as that user** using `sudo -u $VM_USER VBoxManage ...`
3. **Fallback to common usernames** (fedora, sekumar, ubuntu, ec2-user) if `$SUDO_USER` not set

### How It Works

```bash
# Before (broken when run as root)
VMUUID=$(VBoxManage list vms | grep vm- | awk -F '[{}]' '{ print $2 }' | head -n1)

# After (works when run as root)
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

# Run VBoxManage as the VM owner
if [[ -n "$VM_USER" ]]; then
    VMUUID=$(sudo -u "$VM_USER" VBoxManage list vms | grep vm- | awk -F '[{}]' '{ print $2 }' | head -n1)
else
    VMUUID=$(VBoxManage list vms | grep vm- | awk -F '[{}]' '{ print $2 }' | head -n1)
fi
```

## Updated Files

All scripts now detect and use the correct VM owner:

1. ✅ **cf-preserve.sh** - VM detection, state check, savestate
2. ✅ **cf-restore.sh** - VM detection, state check, startvm, config file location
3. ✅ **cf-status.sh** - VM detection and state check
4. ✅ **install-services.sh** - VM detection during installation

## Testing

### Test 1: Run as your user (should work)

```bash
cd /home/sekumar/pcf2ocp/cf-creator/ec2-management
./cf-preserve.sh
```

Expected output:
```
[2026-03-23 17:30:00] Detecting VirtualBox VM for user: fedora...
[2026-03-23 17:30:00] Found VM UUID: ce534bb8-e033-4911-6ff0-1b7a2c1e675a
```

### Test 2: Run as root with sudo (should now work!)

```bash
sudo ./cf-preserve.sh
```

Expected output:
```
[2026-03-23 17:30:00] Detecting VirtualBox VM for user: fedora...
[2026-03-23 17:30:00] Found VM UUID: ce534bb8-e033-4911-6ff0-1b7a2c1e675a
```

### Test 3: Check status

```bash
sudo ./cf-status.sh
```

Should now detect VMs correctly and show:
```
✓ VirtualBox installed
✓ VM found: vm-ce534bb8-e033-4911-6ff0-1b7a2c1e675a
✓ VM State: Running
```

## How Systemd Services Will Work

When systemd runs the services:

1. **Services run as root** (configured in service files)
2. **Scripts detect `$SUDO_USER`** (not available in systemd context)
3. **Scripts try common usernames** (fedora, sekumar, ubuntu, ec2-user)
4. **First user with matching VMs is used**
5. **All VBoxManage commands run as that user**

### Example Service Execution Flow

```
EC2 Shutdown Initiated
    ↓
systemd runs cf-preserve.service (as root)
    ↓
cf-preserve.sh detects VM_USER="fedora"
    ↓
Runs: sudo -u fedora VBoxManage list vms
    ↓
Finds VM: vm-ce534bb8-e033-4911-6ff0-1b7a2c1e675a
    ↓
Runs: sudo -u fedora VBoxManage controlvm vm-... savestate
    ↓
VM state saved successfully!
```

## Important Notes

### Supported Users

The scripts automatically try these usernames:
- `fedora` (Fedora Cloud images)
- `sekumar` (your original username)
- `ubuntu` (Ubuntu Cloud images)
- `ec2-user` (Amazon Linux)

### Adding Custom Usernames

If your VM owner has a different username, edit the detection loop in each script:

```bash
for user in fedora sekumar ubuntu ec2-user YOUR_USERNAME_HERE; do
```

### Why sudo -u instead of su

We use `sudo -u $VM_USER` instead of `su - $VM_USER` because:
1. Simpler syntax
2. Preserves environment variables needed by VBoxManage
3. Works better in systemd context
4. No need for password (when run as root)

## Troubleshooting

### Issue: Still can't detect VMs

**Check VM owner:**
```bash
# Who owns the VirtualBox config?
ls -la ~/.config/VirtualBox/VirtualBox.xml

# Output example:
-rw------- 1 fedora fedora 1234 Mar 23 17:00 VirtualBox.xml
```

The owner (e.g., `fedora`) must be in the detection list.

**Manual test:**
```bash
# Try each user manually
for user in fedora sekumar ubuntu ec2-user; do
    echo "Testing user: $user"
    sudo -u "$user" VBoxManage list vms 2>/dev/null | grep vm- && echo "✓ Found VMs for $user"
done
```

### Issue: Permission denied

**Ensure sudo works without password for VBoxManage:**

Add to `/etc/sudoers.d/vboxmanage`:
```bash
# Allow root to run VBoxManage as any user without password
root ALL=(ALL) NOPASSWD: /usr/bin/VBoxManage
```

Apply with:
```bash
sudo visudo -f /etc/sudoers.d/vboxmanage
```

### Issue: Wrong user detected

**Force a specific user** by editing the scripts:

```bash
# At the top of cf-preserve.sh, cf-restore.sh, cf-status.sh
VM_USER="fedora"  # Force your username
```

## Summary

| Scenario | Before Fix | After Fix |
|----------|-----------|-----------|
| Run as user directly | ✓ Works | ✓ Works |
| Run with sudo | ✗ No VMs found | ✓ Works |
| Systemd service | ✗ No VMs found | ✓ Works |
| Multiple users | ✗ Only root's VMs | ✓ Auto-detects owner |

**Result:** Scripts now work correctly whether run as your user, with sudo, or via systemd services!
