# Cloud Foundry EC2 Management

Automated preservation and restoration of Cloud Foundry VirtualBox VM state on EC2 instance shutdown/startup.

## Overview

This solution automatically saves your Cloud Foundry VirtualBox VM state before EC2 shutdown and restores it on startup, ensuring your deployment persists across EC2 stop/start cycles.

**Key Features:**
- Automatic VM state preservation on EC2 shutdown
- Automatic VM state restoration on EC2 startup
- Notification logging for all operations
- Works with AWS EventBridge scheduled shutdowns
- No manual intervention required

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         EC2 Instance                         │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              EventBridge (Scheduled)                   │  │
│  │         or Manual Shutdown Trigger                     │  │
│  └──────────────────────┬────────────────────────────────┘  │
│                         │                                    │
│                         ▼                                    │
│  ┌───────────────────────────────────────────────────────┐  │
│  │         cf-preserve.service (systemd)                  │  │
│  │  • Triggered before shutdown                           │  │
│  │  • Runs cf-preserve.sh                                 │  │
│  │  • Saves VirtualBox VM state                           │  │
│  │  • Logs notifications                                  │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                               │
│              EC2 STOPPED (VM state preserved)                │
│                                                               │
│              EC2 STARTED (Manual or Scheduled)               │
│                                                               │
│                         │                                    │
│                         ▼                                    │
│  ┌───────────────────────────────────────────────────────┐  │
│  │         cf-restore.service (systemd)                   │  │
│  │  • Triggered on startup                                │  │
│  │  • Runs cf-restore.sh                                  │  │
│  │  • Restores VirtualBox VM state                        │  │
│  │  • Configures network routes                           │  │
│  │  • Logs notifications                                  │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                               │
│         Cloud Foundry Ready and Accessible                   │
└─────────────────────────────────────────────────────────────┘
```

## Components

### Scripts

1. **cf-preserve.sh**
   - Saves VirtualBox VM state before EC2 shutdown
   - Stores VM UUID for restoration
   - Logs all operations with timestamps
   - Sends notifications

2. **cf-restore.sh**
   - Restores VirtualBox VM state on EC2 startup
   - Applies VirtualBox configuration fixes
   - Configures network routes to CF containers
   - Verifies connectivity

3. **install-services.sh**
   - One-time installation script
   - Installs and enables systemd services
   - Sets up logging infrastructure
   - Validates prerequisites

4. **cf-status.sh**
   - Checks overall system status
   - Shows VM state, services, network, and CF status
   - Displays recent notifications
   - Useful for troubleshooting

### Systemd Services

1. **cf-preserve.service**
   - Runs before shutdown/reboot
   - Executes cf-preserve.sh
   - Timeout: 5 minutes

2. **cf-restore.service**
   - Runs on system startup
   - Executes cf-restore.sh
   - Timeout: 10 minutes
   - Auto-retries on failure

## Installation

### Prerequisites

- Cloud Foundry deployed using the main deployment script
- VirtualBox installed and CF VM running
- Sudo/root access
- xmlstarlet (auto-installed if missing)

### Quick Install

```bash
cd /home/sekumar/pcf2ocp/cf-creator/ec2-management
sudo ./install-services.sh
```

The installer will:
1. Check prerequisites (VirtualBox, xmlstarlet)
2. Make scripts executable
3. Install systemd service files
4. Enable services for automatic startup
5. Create log files and state directories

### Verification

After installation, verify the services:

```bash
# Check service status
sudo systemctl status cf-preserve.service
sudo systemctl status cf-restore.service

# Check overall CF status
./cf-status.sh

# Test preserve manually (saves VM state)
sudo systemctl start cf-preserve.service

# Check logs
sudo journalctl -u cf-preserve.service -n 50
sudo journalctl -u cf-restore.service -n 50
```

## AWS EventBridge Setup

### Option 1: Using AWS Console

**Step 1: Create IAM Role for EventBridge**

1. Go to IAM Console → Roles → Create role
2. Select "AWS service" → "EventBridge"
3. Add permission: `AmazonEC2FullAccess` (or create custom policy)
4. Name: `EventBridge-EC2-Stop-Role`

**Step 2: Create EventBridge Rule**

1. Go to Amazon EventBridge Console
2. Click "Create rule"
3. Configure:
   - **Name**: `CF-Daily-Shutdown`
   - **Description**: `Stop EC2 instance with Cloud Foundry daily`
   - **Event bus**: `default`
   - **Rule type**: `Schedule`

4. Set schedule pattern:
   - Choose "Cron expression"
   - Example: `0 22 * * ? *` (10 PM UTC daily)
   - Example: `0 2 * * ? *` (2 AM UTC daily)
   - Adjust to your timezone needs

5. Select target:
   - **Target type**: AWS service
   - **Target**: EC2 StopInstances API call
   - **Instance ID**: Your EC2 instance ID (e.g., `i-1234567890abcdef0`)

6. Review and create

**Step 3: Test the Rule**

1. Wait for scheduled time or manually trigger
2. Check EventBridge metrics
3. Verify EC2 instance stops
4. Check notification logs on EC2:
   ```bash
   sudo tail -f /var/log/cf-shutdown-notifications.log
   ```

### Option 2: Using AWS CLI

```bash
# Set your variables
INSTANCE_ID="i-1234567890abcdef0"
REGION="us-east-1"
SCHEDULE="cron(0 22 * * ? *)"  # 10 PM UTC daily

# Create the rule
aws events put-rule \
  --name CF-Daily-Shutdown \
  --description "Stop EC2 instance with Cloud Foundry daily" \
  --schedule-expression "$SCHEDULE" \
  --region "$REGION"

# Add target (EC2 StopInstances)
aws events put-targets \
  --rule CF-Daily-Shutdown \
  --targets "Id"="1","Arn"="arn:aws:ec2:$REGION:$(aws sts get-caller-identity --query Account --output text):instance/$INSTANCE_ID","RoleArn"="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/EventBridge-EC2-Stop-Role","Input"="{\"InstanceIds\":[\"$INSTANCE_ID\"]}" \
  --region "$REGION"
```

### Option 3: Using CloudFormation

See `eventbridge-cloudformation.yaml` (created separately) for a complete CloudFormation template.

### Cron Expression Examples

```
# Daily at 10 PM UTC
0 22 * * ? *

# Weekdays at 6 PM UTC (Monday-Friday)
0 18 ? * MON-FRI *

# Daily at 2 AM UTC
0 2 * * ? *

# Every 12 hours
0 */12 * * ? *
```

**Note:** EventBridge uses UTC. Convert your local time to UTC for the cron expression.

## Usage

### Daily Workflow

**Automated (Recommended):**

1. EventBridge triggers at scheduled time
2. EC2 receives stop signal
3. `cf-preserve.service` automatically saves VM state
4. EC2 stops
5. When you start EC2 (manually or scheduled):
   - `cf-restore.service` automatically restores VM
   - Cloud Foundry becomes accessible

**No manual intervention needed!**

### Manual Operations

**Check Status:**
```bash
./cf-status.sh
```

**Manually Save VM State:**
```bash
sudo systemctl start cf-preserve.service
# or
sudo ./cf-preserve.sh
```

**Manually Restore VM:**
```bash
sudo systemctl start cf-restore.service
# or
sudo ./cf-restore.sh
```

**Stop EC2 from CLI:**
```bash
aws ec2 stop-instances --instance-ids i-1234567890abcdef0
```

**Start EC2 from CLI:**
```bash
aws ec2 start-instances --instance-ids i-1234567890abcdef0
```

## Monitoring and Logs

### Log Files

```bash
# Preservation logs
sudo tail -f /var/log/cf-preserve.log

# Restoration logs
sudo tail -f /var/log/cf-restore.log

# Shutdown notifications
sudo tail -f /var/log/cf-shutdown-notifications.log

# Startup notifications
sudo tail -f /var/log/cf-startup-notifications.log
```

### Systemd Journal

```bash
# View preserve service logs
sudo journalctl -u cf-preserve.service -f

# View restore service logs
sudo journalctl -u cf-restore.service -f

# View logs from last boot
sudo journalctl -u cf-restore.service -b

# View logs with timestamps
sudo journalctl -u cf-preserve.service --since "1 hour ago"
```

### Notification Log Format

Example notification entries:

```
[2026-03-23 22:00:15] NOTIFICATION: 🔔 Cloud Foundry shutdown initiated - Preserving VM state
[2026-03-23 22:00:18] NOTIFICATION: 💾 Saving Cloud Foundry VM state...
[2026-03-23 22:00:25] NOTIFICATION: ✅ Cloud Foundry VM state saved successfully
```

```
[2026-03-24 08:00:10] NOTIFICATION: 🔔 EC2 instance started - Restoring Cloud Foundry
[2026-03-24 08:00:45] NOTIFICATION: 🚀 Starting Cloud Foundry VM...
[2026-03-24 08:01:20] NOTIFICATION: ✅ Cloud Foundry restored and accessible
[2026-03-24 08:01:22] NOTIFICATION: 🎉 Cloud Foundry restoration complete
```

## Troubleshooting

### VM Not Restoring on Startup

**Check service status:**
```bash
sudo systemctl status cf-restore.service
```

**Check logs:**
```bash
sudo journalctl -u cf-restore.service -n 100
```

**Common issues:**
- VirtualBox not fully started: Wait 30 seconds, check again
- Missing xmlstarlet: Install with `sudo dnf install xmlstarlet`
- Permission issues: Ensure scripts are owned by root and executable

**Manual restore:**
```bash
sudo ./cf-restore.sh
```

### VM Not Saving Before Shutdown

**Check service status:**
```bash
sudo systemctl status cf-preserve.service
```

**Common issues:**
- Service not enabled: `sudo systemctl enable cf-preserve.service`
- Shutdown too fast: Increase timeout in service file
- VM already stopped: Not an error, nothing to save

### Network Route Issues

**Check route:**
```bash
ip route | grep 10.244.0.0
```

**Manually add route:**
```bash
sudo ip route add 10.244.0.0/16 via 192.168.56.6
```

**Test connectivity:**
```bash
ping -c 3 192.168.56.6
ping -c 3 10.244.0.34
```

### EventBridge Not Stopping EC2

**Check EventBridge rule:**
```bash
aws events list-rules --region us-east-1
aws events list-targets-by-rule --rule CF-Daily-Shutdown --region us-east-1
```

**Check IAM permissions:**
- Ensure EventBridge role has EC2 StopInstances permission
- Verify instance ID is correct

**Check EventBridge metrics:**
- Go to CloudWatch → Metrics → Events
- Look for failed invocations

### Checking State Files

```bash
# Check saved VM UUID
cat /home/sekumar/.cf-vm-state/vm-uuid

# Check last save time
date -d @$(cat /home/sekumar/.cf-vm-state/last-saved)

# Check last restore time
date -d @$(cat /home/sekumar/.cf-vm-state/last-restored)
```

## Advanced Configuration

### Adding SNS Notifications

Uncomment SNS sections in `cf-preserve.sh` and `cf-restore.sh`:

```bash
# In cf-preserve.sh and cf-restore.sh, update:
aws sns publish --topic-arn "arn:aws:sns:REGION:ACCOUNT:cf-notifications" \
  --message "$message" 2>/dev/null || true
```

Create SNS topic:
```bash
aws sns create-topic --name cf-notifications
aws sns subscribe --topic-arn arn:aws:sns:REGION:ACCOUNT:cf-notifications \
  --protocol email --notification-endpoint your-email@example.com
```

### Custom Shutdown Times

Edit EventBridge cron expression or create multiple rules:

```bash
# Weekday shutdown at 7 PM
aws events put-rule --name CF-Weekday-Shutdown \
  --schedule-expression "cron(0 19 ? * MON-FRI *)"

# Weekend shutdown at 11 PM
aws events put-rule --name CF-Weekend-Shutdown \
  --schedule-expression "cron(0 23 ? * SAT,SUN *)"
```

### Email Notifications

Install and configure mailx:

```bash
sudo dnf install mailx

# Add to cf-preserve.sh or cf-restore.sh:
echo "$message" | mail -s "CF Notification" your-email@example.com
```

## Uninstallation

To remove the services:

```bash
sudo systemctl stop cf-preserve.service cf-restore.service
sudo systemctl disable cf-preserve.service cf-restore.service
sudo rm /etc/systemd/system/cf-preserve.service
sudo rm /etc/systemd/system/cf-restore.service
sudo systemctl daemon-reload
```

## Files and Directories

```
/home/sekumar/pcf2ocp/cf-creator/ec2-management/
├── cf-preserve.sh              # VM state preservation script
├── cf-restore.sh               # VM state restoration script
├── cf-status.sh                # Status checker
├── install-services.sh         # Installation script
├── cf-preserve.service         # Systemd service for preservation
├── cf-restore.service          # Systemd service for restoration
└── README.md                   # This file

/etc/systemd/system/
├── cf-preserve.service         # Installed preserve service
└── cf-restore.service          # Installed restore service

/var/log/
├── cf-preserve.log             # Preservation operation logs
├── cf-restore.log              # Restoration operation logs
├── cf-shutdown-notifications.log   # Shutdown notifications
└── cf-startup-notifications.log    # Startup notifications

/home/sekumar/.cf-vm-state/
├── vm-uuid                     # Saved VM UUID
├── last-saved                  # Timestamp of last save
└── last-restored               # Timestamp of last restore
```

## Best Practices

1. **Test Before Production:**
   - Test manual preserve/restore before relying on automation
   - Verify EventBridge rule with a test run

2. **Monitor Logs:**
   - Check notification logs regularly
   - Set up alerts for failures

3. **Keep Backups:**
   - EventBridge preserves VM state, but keep BOSH/CF backups
   - Snapshot EBS volumes periodically

4. **Resource Planning:**
   - Ensure EC2 has enough disk space for VM state files
   - Monitor VirtualBox disk usage

5. **Timezone Awareness:**
   - EventBridge uses UTC
   - Convert your local time to UTC for schedules

## Support

For issues:
1. Check `./cf-status.sh` output
2. Review logs in `/var/log/cf-*.log`
3. Check systemd journal: `sudo journalctl -u cf-restore.service`
4. Refer to troubleshooting section above

## References

- [Konveyor CF Deployment Docs](https://github.com/konveyor/asset-generation/blob/main/docs/deploying-cf-locally.md)
- [AWS EventBridge Documentation](https://docs.aws.amazon.com/eventbridge/)
- [Systemd Service Documentation](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
