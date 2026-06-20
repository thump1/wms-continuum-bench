#!/bin/bash
set -euo pipefail

# Run all three experiment sets on the Pegasus HTCondor cluster.
# Execute from Mac — SSHs into VMs as needed.
#
# Experiments:
#   1. Edge-only vs cloud-only placement (per-job timing)
#   2. Latency injection (0, 50, 200ms on edge node)
#   3. Scaled workload (10x100K) on edge-only vs cloud-only

SSH_KEY="$HOME/.ssh/eduardo_ed25519"
CM="pegasus-cm@10.0.1.58"
CLOUD="pegasus-cloud@10.0.1.52"
EDGE="pegasus-edge@10.0.1.54"
PEGASUS_ENV="export PATH=/opt/pegasus-5.1.2/bin:\$PATH && export PEGASUS_HOME=/opt/pegasus-5.1.2"
REPO_DIR="~/wms-continuum-bench/Pegasus"

ssh_cm()  { ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$CM" "$PEGASUS_ENV && $1" 2>&1; }
ssh_cloud() { ssh -tt -i "$SSH_KEY" -o StrictHostKeyChecking=no "$CLOUD" "$1" 2>&1; }
ssh_edge()  { ssh -tt -i "$SSH_KEY" -o StrictHostKeyChecking=no "$EDGE" "$1" 2>&1; }

wait_pipeline() {
    local run_dir="$1"
    while ! ssh_cm "pegasus-status $run_dir" | grep -qE "(Success|Failure)"; do
        sleep 10
    done
    ssh_cm "pegasus-status --long $run_dir"
}

run_iot() {
    local placement="$1"
    local devices="${2:-10}"
    local readings="${3:-10000}"
    echo ""
    echo "============================================"
    echo "  IoT pipeline: --placement $placement"
    echo "  devices=$devices readings=$readings"
    echo "============================================"
    ssh_cm "cd $REPO_DIR && rm -rf work/iot_pipeline results/iot_pipeline && python3 workflows/04_iot_pipeline.py --devices $devices --readings $readings --placement $placement && condor_reschedule 2>/dev/null"
    local run_dir="$REPO_DIR/work/iot_pipeline/pegasus-cm/pegasus/iot-pipeline-wf/run0001"
    local start=$(date +%s)
    wait_pipeline "$run_dir"
    local end=$(date +%s)
    echo "Wall-clock: $((end - start))s"
    echo ""
    echo "--- Per-job timing ---"
    ssh_cm "condor_history -constraint 'ClusterId > 0' -af ClusterId Cmd RemoteWallClockTime LastRemoteHost 2>/dev/null" | grep -E "(simulate|preprocess|stats|aggregate)" | sed 's|.*/\(.*\)\.sh|\1|' | head -35
}

collect_timing() {
    echo ""
    echo "--- Aggregate per-job stats ---"
    ssh_cm 'python3 -c "
import subprocess, re
out = subprocess.check_output([\"condor_history\", \"-af\", \"ClusterId\", \"Cmd\", \"RemoteWallClockTime\", \"LastRemoteHost\"], text=True)
by_type = {}
for line in out.strip().split(chr(10)):
    parts = line.split()
    if len(parts) < 4: continue
    m = re.search(r\"run0001/.*?/([\w_]+)\.sh\", parts[1])
    if not m: continue
    job = re.sub(r\"_ID\d+\", \"\", m.group(1))
    by_type.setdefault(job, []).append(float(parts[2]))
for jt in [\"simulate_sensors_py\", \"edge_preprocess_py\", \"edge_stats_py\", \"cloud_aggregate_py\"]:
    times = by_type.get(jt, [])
    if times:
        print(f\"  {jt:30s}  n={len(times):2d}  avg={sum(times)/len(times):.1f}s  min={min(times):.0f}s  max={max(times):.0f}s\")
total = sum(t for ts in by_type.values() for t in ts)
print(f\"  Total compute: {total:.0f}s\")
"'
}

echo "===== EXPERIMENT 1: Edge-only vs Cloud-only (10x10K) ====="
echo "Starting edge-only run..."
run_iot "edge" 10 10000
collect_timing

echo ""
echo "Starting cloud-only run (fresh)..."
run_iot "cloud" 10 10000
collect_timing

echo ""
echo "===== EXPERIMENT 2: Latency injection (continuum, 10x10K) ====="

for DELAY in 0 50 200; do
    echo ""
    echo "--- Injecting ${DELAY}ms latency on edge node ---"
    ssh_edge "echo pegasus-edge | sudo -S tc qdisc replace dev \$(ip route show default | awk '{print \$5; exit}') root netem delay ${DELAY}ms 2>/dev/null; tc qdisc show dev \$(ip route show default | awk '{print \$5; exit}')"

    run_iot "continuum" 10 10000
    collect_timing
done

echo ""
echo "--- Removing latency ---"
ssh_edge "echo pegasus-edge | sudo -S tc qdisc del dev \$(ip route show default | awk '{print \$5; exit}') root 2>/dev/null || true"

echo ""
echo "===== EXPERIMENT 3: Scaled workload (10x100K) ====="
echo "Starting edge-only (10x100K)..."
run_iot "edge" 10 100000
collect_timing

echo ""
echo "Starting cloud-only (10x100K)..."
run_iot "cloud" 10 100000
collect_timing

echo ""
echo "===== ALL EXPERIMENTS COMPLETE ====="
