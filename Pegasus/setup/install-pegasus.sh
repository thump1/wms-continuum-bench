#!/bin/bash
set -euo pipefail

# Install Pegasus WMS 5.1.2 on the CM/submit node.
# Uses the binary tarball (no apt repo for Ubuntu 26.04).
# Run only on pegasus-cm.

PEGASUS_VERSION="5.1.2"
TARBALL="pegasus-binary-${PEGASUS_VERSION}-x86_64_ubuntu_26.tar.gz"

echo "=== Installing Pegasus WMS ${PEGASUS_VERSION} on $(hostname) ==="

sudo apt-get install -y -qq default-jre-headless
pip install --break-system-packages pegasus-wms

cd /opt
sudo curl -L -o pegasus.tar.gz \
    "https://download.pegasus.isi.edu/pegasus/${PEGASUS_VERSION}/${TARBALL}"
sudo tar xzf pegasus.tar.gz
sudo rm pegasus.tar.gz

echo "export PATH=/opt/pegasus-${PEGASUS_VERSION}/bin:\$PATH" >> ~/.bashrc
echo "export PEGASUS_HOME=/opt/pegasus-${PEGASUS_VERSION}" >> ~/.bashrc

echo "Pegasus version: $(/opt/pegasus-${PEGASUS_VERSION}/bin/pegasus-version)"
echo "=== Done ==="
