#!/bin/bash
set -euo pipefail

# Inject network latency on a Pegasus cluster node using tc netem.
# Usage: ./inject_latency.sh <add|del> <delay_ms>
#
# Must run on an execute node (pegasus-cloud or pegasus-edge) with sudo.
# Affects ALL traffic on the primary interface (eth0 or equivalent).

ACTION="${1:-}"
DELAY="${2:-0}"

IFACE=$(ip route show default | awk '{print $5; exit}')

case "$ACTION" in
  add)
    echo "=== Adding ${DELAY}ms latency on $IFACE ($(hostname)) ==="
    sudo tc qdisc replace dev "$IFACE" root netem delay "${DELAY}ms"
    echo "Verifying:"
    tc qdisc show dev "$IFACE"
    ;;
  del)
    echo "=== Removing latency on $IFACE ($(hostname)) ==="
    sudo tc qdisc del dev "$IFACE" root 2>/dev/null || true
    echo "Cleared."
    ;;
  show)
    echo "=== Current qdisc on $IFACE ($(hostname)) ==="
    tc qdisc show dev "$IFACE"
    ;;
  *)
    echo "Usage: $0 <add|del|show> [delay_ms]"
    exit 1
    ;;
esac
