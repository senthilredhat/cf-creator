# Portability Changes - Dynamic Path Detection

All scripts have been updated to use dynamic path detection instead of hardcoded paths. This makes the entire ec2-management folder portable to any location.

## What Changed

### Before (Hardcoded Paths)
```bash
STATE_DIR="/home/sekumar/.cf-vm-state"
ExecStart=/home/sekumar/pcf2ocp/cf-creator/ec2-management/cf-restore.sh
```

### After (Dynamic Paths)
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$SCRIPT_DIR/.state"
ExecStart=[detected-at-install-time]/cf-restore.sh
```

## Updated Files

### 1. cf-preserve.sh
- ✅ Added `SCRIPT_DIR` detection
- ✅ Changed `STATE_DIR` from `/home/sekumar/.cf-vm-state` to `$SCRIPT_DIR/.state`
- ✅ State files now stored in `.state/` subdirectory next to scripts

### 2. cf-restore.sh
- ✅ Added `SCRIPT_DIR` detection
- ✅ Changed `STATE_DIR` from `/home/sekumar/.cf-vm-state` to `$SCRIPT_DIR/.state`
- ✅ State files now stored in `.state/` subdirectory next to scripts

### 3. cf-status.sh
- ✅ Added `SCRIPT_DIR` detection
- ✅ Changed `STATE_DIR` from `/home/sekumar/.cf-vm-state` to `$SCRIPT_DIR/.state`
- ✅ Reads state files from `.state/` subdirectory

### 4. install-services.sh
- ✅ Already had `SCRIPT_DIR` detection
- ✅ Creates `.state/` directory in script location (not in home directory)
- ✅ Detects actual user with `$SUDO_USER` instead of hardcoded "sekumar"
- ✅ Updates service files with actual script paths before installing
- ✅ Uses `sed` to replace placeholder paths with detected paths

### 5. Service Files (cf-preserve.service, cf-restore.service)
- ℹ️ Still contain placeholder paths: `/home/sekumar/pcf2ocp/cf-creator/ec2-management/`
- ℹ️ These are templates that get updated during installation
- ℹ️ The installer replaces placeholders with actual paths using `sed`

## How It Works

### Installation Process

1. **User runs installer from any location:**
   ```bash
   cd /home/cf-creator/ec2-management  # Could be anywhere!
   sudo ./install-services.sh
   ```

2. **Installer detects location:**
   ```bash
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   # Result: /home/cf-creator/ec2-management
   ```

3. **Installer creates state directory:**
   ```bash
   mkdir -p "$SCRIPT_DIR/.state"
   # Creates: /home/cf-creator/ec2-management/.state
   ```

4. **Installer updates service files:**
   ```bash
   sed "s|/home/sekumar/pcf2ocp/cf-creator/ec2-management|$SCRIPT_DIR|g" \
       cf-preserve.service > /etc/systemd/system/cf-preserve.service
   ```

   Result in `/etc/systemd/system/cf-preserve.service`:
   ```ini
   ExecStop=/home/cf-creator/ec2-management/cf-preserve.sh
   ```

### Runtime Process

When scripts run, they detect their own location:

```bash
# cf-preserve.sh or cf-restore.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$SCRIPT_DIR/.state"

# If script is in /home/cf-creator/ec2-management/
# Then STATE_DIR = /home/cf-creator/ec2-management/.state
```

## File Structure

### New Directory Layout

```
/home/cf-creator/ec2-management/          # Can be anywhere!
├── cf-preserve.sh                        # Auto-detects its location
├── cf-restore.sh                         # Auto-detects its location
├── cf-status.sh                          # Auto-detects its location
├── install-services.sh                   # Auto-detects its location
├── cf-preserve.service                   # Template (updated at install)
├── cf-restore.service                    # Template (updated at install)
├── .state/                               # Created at script location
│   ├── vm-uuid                          # VM identifier
│   ├── last-saved                       # Timestamp
│   └── last-restored                    # Timestamp
└── [other files...]
```

### Logs (Still System-Wide)

These remain in `/var/log/` as they need to be accessible by systemd:

```
/var/log/
├── cf-preserve.log
├── cf-restore.log
├── cf-shutdown-notifications.log
└── cf-startup-notifications.log
```

## Benefits

### ✅ Fully Portable
- Copy the entire `ec2-management/` folder anywhere
- No path changes needed
- Works on any system, any user

### ✅ No Hardcoded Usernames
- Uses `$SUDO_USER` to detect actual user
- Works for any user running the installer
- Proper ownership of state files

### ✅ Self-Contained State
- State files stored with scripts
- Easy to backup/restore (just copy the folder)
- Clear what belongs together

### ✅ Easy Testing
```bash
# Test in different location
cp -r /home/sekumar/pcf2ocp/cf-creator/ec2-management /tmp/test
cd /tmp/test
sudo ./install-services.sh
# Works perfectly!
```

## Migration from Old Setup

If you previously installed with hardcoded paths:

### Option 1: Clean Reinstall (Recommended)
```bash
# Uninstall old services
sudo systemctl stop cf-preserve.service cf-restore.service
sudo systemctl disable cf-preserve.service cf-restore.service
sudo rm /etc/systemd/system/cf-preserve.service
sudo rm /etc/systemd/system/cf-restore.service
sudo systemctl daemon-reload

# Copy old state (if exists)
if [ -d /home/sekumar/.cf-vm-state ]; then
    cp -r /home/sekumar/.cf-vm-state /home/sekumar/pcf2ocp/cf-creator/ec2-management/.state
fi

# Reinstall with new portable version
cd /home/sekumar/pcf2ocp/cf-creator/ec2-management
sudo ./install-services.sh
```

### Option 2: Keep Old State Location
If you prefer the old `/home/sekumar/.cf-vm-state` location, manually edit the scripts to set:
```bash
STATE_DIR="/home/sekumar/.cf-vm-state"  # Instead of $SCRIPT_DIR/.state
```

## Testing Portability

### Test 1: Copy to New Location
```bash
# Copy to different directory
cp -r ec2-management /tmp/cf-test

# Install from new location
cd /tmp/cf-test
sudo ./install-services.sh

# Check service files point to new location
grep ExecStart /etc/systemd/system/cf-restore.service
# Should show: ExecStart=/tmp/cf-test/cf-restore.sh
```

### Test 2: Check State Directory
```bash
# Run status check
cd /tmp/cf-test
./cf-status.sh

# State should be in /tmp/cf-test/.state/
ls -la /tmp/cf-test/.state/
```

### Test 3: Verify Paths
```bash
# Check what paths scripts are using
cd /tmp/cf-test
grep "STATE_DIR=" cf-preserve.sh
# Should show: STATE_DIR="$SCRIPT_DIR/.state"
```

## Summary

All hardcoded paths have been eliminated:

| Component | Old Path | New Path |
|-----------|----------|----------|
| State Directory | `/home/sekumar/.cf-vm-state` | `$SCRIPT_DIR/.state` |
| Preserve Script | Hardcoded in service | Detected at install |
| Restore Script | Hardcoded in service | Detected at install |
| User/Group | Hardcoded "sekumar" | Detected via `$SUDO_USER` |

**Result:** The entire `ec2-management/` folder is now fully portable and can be moved to any location on any system without modification.
