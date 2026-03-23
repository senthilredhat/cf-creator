# AWS EventBridge Setup Guide

Complete guide for setting up automated EC2 shutdown using AWS EventBridge.

## Quick Start

### Option 1: CloudFormation (Recommended)

```bash
# Set your parameters
INSTANCE_ID="i-1234567890abcdef0"
SCHEDULE="cron(0 22 * * ? *)"  # 10 PM UTC daily
EMAIL="your-email@example.com"
REGION="us-east-1"

# Deploy the stack
aws cloudformation create-stack \
  --stack-name cf-ec2-shutdown \
  --template-body file://eventbridge-cloudformation.yaml \
  --parameters \
    ParameterKey=EC2InstanceId,ParameterValue=$INSTANCE_ID \
    ParameterKey=ShutdownSchedule,ParameterValue="$SCHEDULE" \
    ParameterKey=Region,ParameterValue=$REGION \
    ParameterKey=SNSEmailAddress,ParameterValue=$EMAIL \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $REGION

# Check stack status
aws cloudformation describe-stacks \
  --stack-name cf-ec2-shutdown \
  --region $REGION \
  --query 'Stacks[0].StackStatus'
```

**Next Steps:**
1. Tag your EC2 instance:
   ```bash
   aws ec2 create-tags \
     --resources $INSTANCE_ID \
     --tags Key=ManagedBy,Value=CloudFormation-CF-Shutdown \
     --region $REGION
   ```

2. Confirm SNS subscription email

3. Wait for scheduled time or test manually

### Option 2: AWS Console (Step-by-Step)

#### Step 1: Create IAM Role

1. **Navigate to IAM Console**
   - Go to: https://console.aws.amazon.com/iam/

2. **Create Role**
   - Click "Roles" → "Create role"
   - **Trusted entity type**: AWS service
   - **Use case**: EventBridge
   - Click "Next"

3. **Create Custom Policy**
   - Click "Create policy"
   - Choose JSON tab
   - Paste this policy:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "ec2:StopInstances",
           "ec2:DescribeInstances"
         ],
         "Resource": "*"
       }
     ]
   }
   ```
   - Name it: `EC2-Stop-Policy`
   - Click "Create policy"

4. **Attach Policy to Role**
   - Back in role creation, refresh and select `EC2-Stop-Policy`
   - Click "Next"
   - **Role name**: `EventBridge-EC2-Stop-Role`
   - Click "Create role"

#### Step 2: Create EventBridge Rule

1. **Navigate to EventBridge Console**
   - Go to: https://console.aws.amazon.com/events/

2. **Create Rule**
   - Click "Create rule"
   - **Name**: `CF-Daily-Shutdown`
   - **Description**: `Stop Cloud Foundry EC2 instance daily`
   - **Event bus**: default
   - Click "Next"

3. **Define Schedule Pattern**
   - **Rule type**: Schedule
   - **Schedule pattern**: Cron expression
   - **Cron expression**: `0 22 * * ? *` (or your preferred time)
   - **Flexible time window**: Off
   - Click "Next"

4. **Select Target**
   - **Target types**: AWS service
   - **Select a target**: EC2 StopInstances API call
   - **Instance ID(s)**: Your EC2 instance ID (e.g., `i-1234567890abcdef0`)
   - **Execution role**: Use existing role
   - **Existing role**: `EventBridge-EC2-Stop-Role`
   - Click "Next"

5. **Configure Tags (Optional)**
   - Add tags if desired
   - Click "Next"

6. **Review and Create**
   - Review all settings
   - Click "Create rule"

#### Step 3: Verify Setup

1. **Check Rule Status**
   - Go to EventBridge → Rules
   - Find `CF-Daily-Shutdown`
   - Status should be "Enabled"

2. **Test the Rule (Optional)**
   - Select the rule
   - Click "Actions" → "Disable"
   - Create a test rule with "rate(5 minutes)"
   - Test it stops your EC2
   - Delete test rule, re-enable original

### Option 3: AWS CLI (Quick)

```bash
# Variables
INSTANCE_ID="i-1234567890abcdef0"
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create IAM role trust policy
cat > /tmp/trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create IAM role
aws iam create-role \
  --role-name EventBridge-EC2-Stop-Role \
  --assume-role-policy-document file:///tmp/trust-policy.json

# Create IAM policy
cat > /tmp/ec2-stop-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:StopInstances",
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Create and attach policy
aws iam create-policy \
  --policy-name EC2-Stop-Policy \
  --policy-document file:///tmp/ec2-stop-policy.json

aws iam attach-role-policy \
  --role-name EventBridge-EC2-Stop-Role \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/EC2-Stop-Policy

# Create EventBridge rule
aws events put-rule \
  --name CF-Daily-Shutdown \
  --description "Stop Cloud Foundry EC2 instance daily" \
  --schedule-expression "cron(0 22 * * ? *)" \
  --region $REGION

# Add EC2 StopInstances as target
aws events put-targets \
  --rule CF-Daily-Shutdown \
  --targets "Id=1,Arn=arn:aws:ec2:${REGION}:${ACCOUNT_ID}:instance/${INSTANCE_ID},RoleArn=arn:aws:iam::${ACCOUNT_ID}:role/EventBridge-EC2-Stop-Role,Input={\\\"InstanceIds\\\":[\\\"${INSTANCE_ID}\\\"]}" \
  --region $REGION

# Verify
aws events list-targets-by-rule \
  --rule CF-Daily-Shutdown \
  --region $REGION
```

## Cron Expression Examples

EventBridge uses cron expressions with 6 fields: `minute hour day month day-of-week year`

**Common Schedules:**

```bash
# Daily at 10 PM UTC
cron(0 22 * * ? *)

# Daily at 2 AM UTC
cron(0 2 * * ? *)

# Weekdays at 6 PM UTC (Monday-Friday)
cron(0 18 ? * MON-FRI *)

# Weekends at 11 PM UTC
cron(0 23 ? * SAT,SUN *)

# Every 12 hours
cron(0 */12 * * ? *)

# Every day at 8 PM EST (1 AM UTC next day)
cron(0 1 * * ? *)

# Every day at 5:30 PM PST (1:30 AM UTC next day)
cron(30 1 * * ? *)
```

**Timezone Conversion:**

EventBridge uses **UTC only**. Convert your local time:

- **EST (UTC-5)**: 6 PM EST = 11 PM UTC (23:00)
- **PST (UTC-8)**: 6 PM PST = 2 AM UTC next day (02:00)
- **CST (UTC-6)**: 6 PM CST = 12 AM UTC next day (00:00)
- **EDT (UTC-4)**: 6 PM EDT = 10 PM UTC (22:00)

Use this formula: `UTC = Local Time + Offset`

## Testing Your Setup

### Test 1: Verify Rule Created

```bash
aws events describe-rule --name CF-Daily-Shutdown --region us-east-1
```

Expected output:
```json
{
    "Name": "CF-Daily-Shutdown",
    "Arn": "arn:aws:events:us-east-1:123456789012:rule/CF-Daily-Shutdown",
    "State": "ENABLED",
    "ScheduleExpression": "cron(0 22 * * ? *)"
}
```

### Test 2: Verify Target Configured

```bash
aws events list-targets-by-rule \
  --rule CF-Daily-Shutdown \
  --region us-east-1
```

Should show EC2 instance as target.

### Test 3: Manual Test (Careful!)

**Create a test rule that runs in 5 minutes:**

```bash
# Get current time + 5 minutes in UTC
CURRENT_UTC=$(date -u +"%H")
CURRENT_MIN=$(date -u +"%M")
TEST_MIN=$((CURRENT_MIN + 5))

# Create test rule
aws events put-rule \
  --name CF-Shutdown-Test \
  --description "Test rule - runs once in 5 min" \
  --schedule-expression "cron($TEST_MIN $CURRENT_UTC * * ? *)" \
  --region us-east-1

# Add same target
aws events put-targets \
  --rule CF-Shutdown-Test \
  --targets "Id=1,Arn=arn:aws:ec2:us-east-1:$ACCOUNT_ID:instance/$INSTANCE_ID,RoleArn=arn:aws:iam::$ACCOUNT_ID:role/EventBridge-EC2-Stop-Role" \
  --region us-east-1

# Wait 5 minutes, verify EC2 stops

# Delete test rule
aws events remove-targets --rule CF-Shutdown-Test --ids 1 --region us-east-1
aws events delete-rule --name CF-Shutdown-Test --region us-east-1
```

### Test 4: Check on EC2 Instance

After scheduled time:

```bash
# Check instance state
aws ec2 describe-instances \
  --instance-ids i-1234567890abcdef0 \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text
```

Should return: `stopped` or `stopping`

## Monitoring

### CloudWatch Metrics

1. Go to CloudWatch Console
2. Navigate to "Metrics" → "Events"
3. Look for metrics related to `CF-Daily-Shutdown`

**Key Metrics:**
- `Invocations`: Number of times rule triggered
- `FailedInvocations`: Failed executions
- `TriggeredRules`: Successfully triggered

### CloudWatch Logs

If you set up logging in CloudFormation:

```bash
# View shutdown events
aws logs tail /aws/events/cf-shutdown --follow --region us-east-1
```

### EventBridge Event History

```bash
# List recent events
aws events describe-event-bus \
  --name default \
  --region us-east-1
```

## Notifications Setup (Optional)

### SNS Email Notifications

**Create SNS Topic:**
```bash
aws sns create-topic --name CF-Shutdown-Notifications --region us-east-1
```

**Subscribe Email:**
```bash
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:$ACCOUNT_ID:CF-Shutdown-Notifications \
  --protocol email \
  --notification-endpoint your-email@example.com \
  --region us-east-1
```

**Confirm subscription in email**

**Update EventBridge Rule to Send SNS:**
```bash
aws events put-targets \
  --rule CF-Daily-Shutdown \
  --targets "Id=2,Arn=arn:aws:sns:us-east-1:$ACCOUNT_ID:CF-Shutdown-Notifications" \
  --region us-east-1
```

### Lambda Function Notification (Advanced)

Create a Lambda function to send custom notifications before shutdown.

## Troubleshooting

### Issue: EventBridge Rule Not Triggering

**Check:**
1. Rule is enabled:
   ```bash
   aws events describe-rule --name CF-Daily-Shutdown --region us-east-1
   ```

2. Cron expression is correct (use UTC)

3. IAM role has correct permissions

4. Check CloudWatch Events metrics for failures

### Issue: EC2 Not Stopping

**Check:**
1. IAM role has `ec2:StopInstances` permission

2. Instance ID is correct:
   ```bash
   aws events list-targets-by-rule --rule CF-Daily-Shutdown --region us-east-1
   ```

3. No instance protection enabled:
   ```bash
   aws ec2 describe-instance-attribute \
     --instance-id i-1234567890abcdef0 \
     --attribute disableApiTermination \
     --region us-east-1
   ```

### Issue: Wrong Time Zone

**Problem:** EC2 stops at wrong time

**Solution:** EventBridge uses UTC only. Convert your local time to UTC.

Example: If you want 10 PM EST:
- EST is UTC-5
- 10 PM + 5 hours = 3 AM UTC next day
- Cron: `cron(0 3 * * ? *)`

## Modifying the Schedule

### Change Shutdown Time

```bash
# Update to new schedule (e.g., 11 PM UTC)
aws events put-rule \
  --name CF-Daily-Shutdown \
  --schedule-expression "cron(0 23 * * ? *)" \
  --region us-east-1
```

### Disable Scheduled Shutdown

```bash
# Disable the rule
aws events disable-rule --name CF-Daily-Shutdown --region us-east-1

# Re-enable when needed
aws events enable-rule --name CF-Daily-Shutdown --region us-east-1
```

### Delete the Rule

```bash
# Remove targets first
aws events remove-targets \
  --rule CF-Daily-Shutdown \
  --ids 1 \
  --region us-east-1

# Delete the rule
aws events delete-rule \
  --name CF-Daily-Shutdown \
  --region us-east-1
```

## Integration with EC2 Instance

On your EC2 instance, the systemd services handle everything automatically:

1. **Before Shutdown:**
   - EventBridge triggers EC2 stop
   - EC2 initiates shutdown sequence
   - `cf-preserve.service` runs automatically
   - VM state saved
   - Notification logged
   - EC2 stops

2. **After Startup:**
   - You start EC2 manually (or via another EventBridge rule)
   - `cf-restore.service` runs automatically on boot
   - VM state restored
   - Network configured
   - Notification logged
   - CF ready

**No manual intervention needed!**

## Cost Considerations

**EventBridge Pricing:**
- First 1 million events per month: Free
- Additional events: $1.00 per million

**For daily shutdown:**
- 1 event per day × 30 days = 30 events/month
- **Cost: $0** (well within free tier)

**Additional Costs:**
- CloudWatch Logs: Minimal
- SNS notifications: $0.50 per million (first 1,000 free)
- Lambda (if used): Minimal

**Total estimated cost: < $1/month**

## Security Best Practices

1. **Least Privilege IAM:**
   - Only grant `ec2:StopInstances` permission
   - Don't use `ec2:*` or `*:*`

2. **Resource Tags:**
   - Tag EC2 instances managed by EventBridge
   - Use conditions in IAM policies

3. **Enable CloudTrail:**
   - Track all EventBridge API calls
   - Audit who changes rules

4. **VPC Security:**
   - EventBridge works with EC2 in any subnet
   - No changes to security groups needed

## Automated Startup (Optional)

To also automate EC2 startup:

```bash
# Create startup rule (e.g., 8 AM UTC daily)
aws events put-rule \
  --name CF-Daily-Startup \
  --description "Start Cloud Foundry EC2 instance daily" \
  --schedule-expression "cron(0 8 * * ? *)" \
  --region us-east-1

# Add EC2 StartInstances as target
aws events put-targets \
  --rule CF-Daily-Startup \
  --targets "Id=1,Arn=arn:aws:ec2:$REGION:$ACCOUNT_ID:instance/$INSTANCE_ID,RoleArn=arn:aws:iam::$ACCOUNT_ID:role/EventBridge-EC2-Start-Role,Input={\\\"InstanceIds\\\":[\\\"$INSTANCE_ID\\\"]}" \
  --region $REGION
```

Note: Requires additional IAM permission `ec2:StartInstances`

## Summary Checklist

- [ ] IAM role created with `ec2:StopInstances` permission
- [ ] EventBridge rule created with correct cron expression
- [ ] EC2 instance ID configured as target
- [ ] Rule is enabled
- [ ] Systemd services installed on EC2 (from main installation)
- [ ] Tested manually or waited for scheduled time
- [ ] Verified EC2 stops at scheduled time
- [ ] Verified CF restores on EC2 startup
- [ ] Notifications working (if configured)
- [ ] CloudWatch metrics monitored

## References

- [EventBridge Schedule Expressions](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-rule-schedule.html)
- [EventBridge Cron Expressions](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-cron-expressions.html)
- [EC2 StopInstances API](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_StopInstances.html)
