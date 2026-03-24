# Cloud Foundry Environment Usage Guide

This guide explains how to access and use the Cloud Foundry environment for testing and development.

## Accessing CF from the EC2 Instance

### Step 1: Login to the EC2 Instance

Connect to the EC2 instance where the Cloud Foundry environment is deployed.

### Step 2: Source the CF Login Script

Run the following command to load the Cloud Foundry login script:

```bash
source ./cf-login.sh
```

### Step 3: Select the RedHat Space

When prompted, select option **1** to use the `redhat` space.

### Step 4: Verify Access

You can verify your access by listing the deployed applications:

```bash
cf apps
```

### CF Admin Password

The CF admin password is stored in the `CF_ADMIN_PASSWORD` environment variable on the EC2 instance.

## Accessing CF from Your Local Machine

If you want to access the Cloud Foundry instance from your local machine:

### Step 1: Configure Local CF Client

```bash
ssh fedora@<remote_server_address> -i <path_to/private/sshkey>
```
> Note: Use the path to your private SSH key, not the public key.

* Set up the SSH tunnel on your local machine:

```bash
sudo ssh -v -N \
  -i <path_to/private/sshkey> \
  -L 443:10.244.0.131:443 \
  -L 8443:10.244.0.34:443 \
  -L 8444:10.244.0.131:443 \
  fedora@<remote_server_address>
```

> Extra info:<br/>
> The `-N` flag tells SSH not to execute a remote command.<br/>
> The `-v` flag enables verbose output for debugging.

### Step 2: Login from Local Machine

Use the following command to login (replace `$CF_ADMIN_PASSWORD` with the password from the EC2 instance):

```bash
cf login -a https://api.bosh-lite.com --skip-ssl-validation -u admin -p "$CF_ADMIN_PASSWORD"
```

**Note:** You need to obtain the `CF_ADMIN_PASSWORD` value from the EC2 instance first.

## Common Commands

- `cf apps` - List all applications
- `cf services` - List all services
- `cf target` - Show current target information
- `cf help` - Show all available commands
