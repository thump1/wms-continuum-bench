#!/usr/bin/env bash
# Remove tc netem latency from a k3d node.
#
# Usage:
#   ./scripts/tc-remove-latency.sh <node>
#   ./scripts/tc-remove-latency.sh all    # remove from both edge and cloud nodes

set -euo pipefail

remove_netem() {
    local node="$1"
    echo "Removing latency from ${node}..."
    docker run --rm \
        --net=container:"${node}" \
        --cap-add NET_ADMIN \
        alpine sh -c "
            apk add -q iproute2 2>/dev/null
            tc qdisc del dev eth0 root 2>/dev/null || true
            echo 'Restored qdisc:'
            tc qdisc show dev eth0
        "
}

NODE="${1:?Usage: $0 <node|all>}"

if [ "$NODE" = "all" ]; then
    remove_netem k3d-continuum-agent-0
    remove_netem k3d-continuum-agent-1
else
    remove_netem "$NODE"
fi
