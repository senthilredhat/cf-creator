#!/bin/bash

echo "=== VirtualBox VM Detection Test ==="
echo ""

echo "Current user: $(whoami)"
echo "Current UID: $(id -u)"
echo "Home directory: $HOME"
echo ""

echo "VBoxManage command location:"
which VBoxManage
echo ""

echo "Running: VBoxManage list vms"
VBoxManage list vms
echo ""

echo "Running: VBoxManage list vms | grep vm-"
VBoxManage list vms | grep vm-
echo ""

echo "Extracting UUID:"
VMUUID=$(VBoxManage list vms | grep vm- | awk -F '[{}]' '{ print $2 }' | head -n1)
echo "VMUUID='$VMUUID'"
if [[ -z "$VMUUID" ]]; then
    echo "ERROR: VMUUID is empty!"
else
    echo "SUCCESS: VMUUID found: $VMUUID"
fi
