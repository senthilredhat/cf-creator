# Quick Start Guide

Get your Cloud Foundry EC2 management up and running in 5 minutes.

## Prerequisites

✅ Cloud Foundry already deployed using the main deployment script
✅ VirtualBox VM running
✅ EC2 instance accessible
✅ Sudo/root access

## Step 1: Install the Services (2 minutes)

```bash
# Navigate to the ec2-management directory in your cloned repository
cd ec2-management
sudo ./install-services.sh
```

**What this does:**
- Installs systemd services for automatic preserve/restore
- Creates log files
- Enables services to run on shutdown/startup

**Expected output:**
```
✓ VirtualBox found
✓ Scripts made executable
✓ Service files copied
✓ Services enabled
✓ Installation completed successfully!
```

## Step 2: Verify Installation (1 minute)

```bash
# Check system status
./cf-status.sh
```

**You should see:**
- ✓ VirtualBox installed
- ✓ VM found and running
- ✓ cf-preserve.service enabled
- ✓ cf-restore.service enabled
- ✓ Network route configured
- ✓ BOSH Director reachable

## Step 3: Test the Services (2 minutes)

**Test save (preserve):**
```bash
sudo systemctl start cf-preserve.service
sudo journalctl -u cf-preserve.service -n 20
```

**Expected in logs:**
```
Cloud Foundry shutdown initiated
Saving Cloud Foundry VM state...
✅ Cloud Foundry VM state saved successfully
```

**Test restore:**
```bash
sudo systemctl start cf-restore.service
sudo journalctl -u cf-restore.service -n 20
```

**Expected in logs:**
```
EC2 instance started - Restoring Cloud Foundry
Starting Cloud Foundry VM...
✅ Cloud Foundry restored and accessible
```

## Step 4: Setup AWS EventBridge (5 minutes)

Choose one method:

### Option A: CloudFormation (Easiest)

```bash
# Set your details
INSTANCE_ID="i-1234567890abcdef0"  # Replace with your EC2 instance ID
EMAIL="your-email@example.com"      # Your email for notifications
SCHEDULE="cron(0 22 * * ? *)"      # 10 PM UTC daily

# Deploy
aws cloudformation create-stack \
  --stack-name cf-ec2-shutdown \
  --template-body file://eventbridge-cloudformation.yaml \
  --parameters \
    ParameterKey=EC2InstanceId,ParameterValue=$INSTANCE_ID \
    ParameterKey=ShutdownSchedule,ParameterValue="$SCHEDULE" \
    ParameterKey=SNSEmailAddress,ParameterValue=$EMAIL \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# Tag your instance
aws ec2 create-tags \
  --resources $INSTANCE_ID \
  --tags Key=ManagedBy,Value=CloudFormation-CF-Shutdown \
  --region us-east-1

# Confirm SNS subscription email
```

### Option B: AWS Console (Manual)

Follow the detailed steps in `EVENTBRIDGE-SETUP.md`

## Step 5: Monitor (Ongoing)

### Check Notification Logs

```bash
# Shutdown notifications
sudo tail -f /var/log/cf-shutdown-notifications.log

# Startup notifications
sudo tail -f /var/log/cf-startup-notifications.log
```

### Check System Status

```bash
./cf-status.sh
```

### View Service Logs

```bash
# Preserve service
sudo journalctl -u cf-preserve.service -f

# Restore service
sudo journalctl -u cf-restore.service -f
```

## Daily Workflow

**Automated (Default):**

1. EventBridge stops EC2 at scheduled time (e.g., 10 PM)
2. `cf-preserve.service` automatically saves VM state
3. EC2 stops
4. You manually start EC2 when needed (or use another EventBridge rule)
5. `cf-restore.service` automatically restores VM on boot
6. Cloud Foundry ready to use

**No manual steps required!**

## Common Commands

```bash
# Check status
./cf-status.sh

# View shutdown notifications
sudo tail /var/log/cf-shutdown-notifications.log

# View startup notifications
sudo tail /var/log/cf-startup-notifications.log

# Manually save VM state
sudo systemctl start cf-preserve.service

# Manually restore VM
sudo systemctl start cf-restore.service

# Check service status
sudo systemctl status cf-preserve.service
sudo systemctl status cf-restore.service
```

## Timezone Reference

EventBridge uses **UTC only**. Convert your local time:

```
EST (UTC-5):  6 PM EST = 11 PM UTC → cron(0 23 * * ? *)
CST (UTC-6):  6 PM CST = 12 AM UTC → cron(0 0 * * ? *)
PST (UTC-8):  6 PM PST = 2 AM UTC  → cron(0 2 * * ? *)
EDT (UTC-4):  6 PM EDT = 10 PM UTC → cron(0 22 * * ? *)
```

Use: [Time Zone Converter](https://www.timeanddate.com/worldclock/converter.html)

## Troubleshooting

### Services not running?

```bash
sudo systemctl status cf-preserve.service
sudo systemctl status cf-restore.service

# If not enabled:
sudo systemctl enable cf-preserve.service
sudo systemctl enable cf-restore.service
```

### VM not restoring after reboot?

```bash
# Check logs
sudo journalctl -u cf-restore.service -n 100

# Manually restore
sudo ./cf-restore.sh
```

### Network route missing?

```bash
# Check route
ip route | grep 10.244.0.0

# Add manually
sudo ip route add 10.244.0.0/16 via 192.168.56.6
```

### EventBridge not stopping EC2?

```bash
# Check rule status
aws events describe-rule --name CF-Daily-Shutdown --region us-east-1

# Check targets
aws events list-targets-by-rule --rule CF-Daily-Shutdown --region us-east-1

# Enable if disabled
aws events enable-rule --name CF-Daily-Shutdown --region us-east-1
```

## Next Steps

1. ✅ Services installed and tested
2. ✅ EventBridge configured
3. 📧 Confirm SNS subscription email
4. ⏰ Wait for scheduled shutdown time (or test manually)
5. 📊 Monitor logs to verify automation works
6. 🎉 Enjoy automated CF management!

## Files Overview

```
ec2-management/
├── QUICKSTART.md              ← You are here
├── README.md                  ← Full documentation
├── EVENTBRIDGE-SETUP.md       ← EventBridge detailed guide
├── cf-preserve.sh             ← Saves VM state
├── cf-restore.sh              ← Restores VM state
├── cf-status.sh               ← Status checker
├── install-services.sh        ← Installation script
├── cf-preserve.service        ← Systemd preserve service
├── cf-restore.service         ← Systemd restore service
└── eventbridge-cloudformation.yaml  ← CloudFormation template
```

## Support

- **Full documentation**: See `README.md`
- **EventBridge setup**: See `EVENTBRIDGE-SETUP.md`
- **Check status**: Run `./cf-status.sh`
- **View logs**: Check `/var/log/cf-*.log`

---

**That's it! Your Cloud Foundry EC2 instance is now managed automatically.**

🎯 Test it by waiting for the scheduled shutdown time or manually stopping EC2.
🚀 When you start EC2, Cloud Foundry will be automatically restored.
