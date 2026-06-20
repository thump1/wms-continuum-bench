#!/bin/bash
set -euo pipefail

# Install Pegasus WMS on the CM/submit node.
# Run only on pegasus-cm.

echo "=== Installing Pegasus WMS on $(hostname) ==="

# Add Pegasus repo
echo "deb [trusted=yes] http://download.pegasus.isi.edu/wms/download/debian resolute main" | \
    sudo tee /etc/apt/sources.list.d/pegasus.list

sudo apt-get update -qq
sudo apt-get install -y pegasus

echo "Pegasus version: $(pegasus-version)"
echo "=== Done ==="
