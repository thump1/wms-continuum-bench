#!/usr/bin/env bash
# Inject network latency on a k3d node using tc netem.
# Runs a privileged Alpine sidecar sharing the node's network namespace.
#
# Usage:
#   ./scripts/tc-inject-latency.sh <node> <delay_ms> [jitter_ms]
#
# Examples:
#   ./scripts/tc-inject-latency.sh k3d-continuum-agent-1 200      # 200ms fixed
#   ./scripts/tc-inject-latency.sh k3d-continuum-agent-1 200 50   # 200ms ± 50ms
#
# Remove with:
#   ./scripts/tc-remove-latency.sh <node>

set -euo pipefail

NODE="${1:?Usage: $0 <node> <delay_ms> [jitter_ms]}"
DELAY="${2:?Usage: $0 <node> <delay_ms> [jitter_ms]}"
JITTER="${3:-0}"

if [ "$JITTER" -gt 0 ] 2>/dev/null; then
    NETEM_ARGS="delay ${DELAY}ms ${JITTER}ms distribution normal"
else
    NETEM_ARGS="delay ${DELAY}ms"
fi

echo "Injecting latency on ${NODE}: ${NETEM_ARGS}"

docker run --rm \
    --net=container:"${NODE}" \
    --cap-add NET_ADMIN \
    alpine sh -c "
        apk add -q iproute2 2>/dev/null
        tc qdisc del dev eth0 root 2>/dev/null || true
        tc qdisc add dev eth0 root netem ${NETEM_ARGS}
        echo 'Active qdisc:'
        tc qdisc show dev eth0
    "
