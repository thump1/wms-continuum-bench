#!/bin/bash
set -euo pipefail

# Configure HTCondor cluster role.
# Usage: ./configure-cluster.sh <role>
# Roles: cm, cloud, edge

if [ $# -ne 1 ]; then
    echo "Usage: $0 <cm|cloud|edge>"
    exit 1
fi

ROLE="$1"

case "$ROLE" in
  cm)
    echo "=== Configuring Central Manager (pegasus-cm) ==="
    sudo tee /etc/condor/config.d/00-cm.config << 'EOF'
CONDOR_HOST = pegasus-cm
DAEMON_LIST = MASTER COLLECTOR NEGOTIATOR SCHEDD

NEGOTIATOR_INTERVAL = 20

ALLOW_WRITE = 10.0.1.*
ALLOW_READ  = 10.0.1.*

SEC_DEFAULT_AUTHENTICATION_METHODS = IDTOKENS
SEC_CLIENT_AUTHENTICATION_METHODS  = IDTOKENS

SEC_TOKEN_DIRECTORY = /etc/condor/tokens.d
EOF
    sudo mkdir -p /etc/condor/tokens.d
    sudo systemctl restart condor
    echo "CM configured and restarted."
    ;;

  cloud)
    echo "=== Configuring Execute node: cloud (pegasus-cloud) ==="
    sudo tee /etc/condor/config.d/00-execute.config << 'EOF'
CONDOR_HOST = pegasus-cm
DAEMON_LIST = MASTER STARTD

ContinuumTier = "cloud"
STARTD_ATTRS = $(STARTD_ATTRS) ContinuumTier

SEC_DEFAULT_AUTHENTICATION_METHODS = IDTOKENS
SEC_CLIENT_AUTHENTICATION_METHODS  = IDTOKENS

SEC_TOKEN_DIRECTORY = /etc/condor/tokens.d
EOF
    sudo mkdir -p /etc/condor/tokens.d
    sudo systemctl restart condor
    echo "Cloud execute node configured and restarted."
    ;;

  edge)
    echo "=== Configuring Execute node: edge (pegasus-edge) ==="
    sudo tee /etc/condor/config.d/00-execute.config << 'EOF'
CONDOR_HOST = pegasus-cm
DAEMON_LIST = MASTER STARTD

ContinuumTier = "edge"
STARTD_ATTRS = $(STARTD_ATTRS) ContinuumTier

SEC_DEFAULT_AUTHENTICATION_METHODS = IDTOKENS
SEC_CLIENT_AUTHENTICATION_METHODS  = IDTOKENS

SEC_TOKEN_DIRECTORY = /etc/condor/tokens.d
EOF
    sudo mkdir -p /etc/condor/tokens.d
    sudo systemctl restart condor
    echo "Edge execute node configured and restarted."
    ;;

  *)
    echo "Unknown role: $ROLE. Use cm, cloud, or edge."
    exit 1
    ;;
esac

echo "=== Done configuring $ROLE on $(hostname) ==="
