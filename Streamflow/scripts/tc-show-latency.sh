#!/usr/bin/env bash
# Show current tc netem configuration on k3d nodes.

set -euo pipefail

for node in k3d-continuum-agent-0 k3d-continuum-agent-1; do
    label=$(docker inspect "$node" --format '{{index .Config.Labels "k3d.role"}}' 2>/dev/null || echo "?")
    tier=$(kubectl get node "$node" -o jsonpath='{.metadata.labels.continuum-tier}' 2>/dev/null || echo "?")
    echo "=== ${node} (${tier}) ==="
    docker run --rm \
        --net=container:"${node}" \
        --cap-add NET_ADMIN \
        alpine sh -c "apk add -q iproute2 2>/dev/null; tc qdisc show dev eth0"
    echo ""
done
