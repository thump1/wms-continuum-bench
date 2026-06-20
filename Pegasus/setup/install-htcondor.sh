#!/bin/bash
set -euo pipefail

# Install HTCondor 25.x on Ubuntu 26.04 (Resolute Raccoon).
# Run on all 3 nodes: CM, cloud, edge.

echo "=== Installing HTCondor on $(hostname) ==="

# Add HTCondor GPG key
curl -fsSL https://research.cs.wisc.edu/htcondor/repo/keys/HTCondor-25.x-Key | \
    sudo gpg --dearmor -o /usr/share/keyrings/htcondor-archive-keyring.gpg

# Add HTCondor repo for resolute
echo "deb [signed-by=/usr/share/keyrings/htcondor-archive-keyring.gpg] \
https://research.cs.wisc.edu/htcondor/repo/ubuntu/25.x resolute main" | \
    sudo tee /etc/apt/sources.list.d/htcondor.list

sudo apt-get update -qq
sudo apt-get install -y htcondor

echo "HTCondor version: $(condor_version)"
echo "=== Done ==="
