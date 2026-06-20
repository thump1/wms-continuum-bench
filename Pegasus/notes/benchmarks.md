# Benchmark notes — Pegasus WMS

Free-form log of observations and measurements during the Pegasus POC.
Structured data feeds cross-SWMS comparison tables in the thesis.

## Infrastructure

| VM | Hostname | Role | vCPU | RAM | IP |
|----|----------|------|------|-----|----|
| CM/Submit | pegasus-cm | Central Manager + Schedd | 2 | 3.3 GB | 10.0.1.58 |
| Cloud exec | pegasus-cloud | Execute node (cloud tier) | 4 | 15 GB | 10.0.1.52 |
| Edge exec | pegasus-edge | Execute node (edge tier) | 2 | 7.2 GB | 10.0.1.54 |

All Ubuntu 26.04 LTS on VMware Workstation Pro (Ryzen 7-3700X, 64 GB host).
HTCondor 25.11.0, Pegasus 5.1.2, Python 3.14.4.

**Hardware asymmetry**: Edge has 2 vCPU vs Cloud's 4 vCPU, modelling real continuum resource constraints.

## Run log

---

## Runs

### 2026-06-20 — Hello (4 greetings, any placement)
- **Workflow**: `workflows/00_hello.py`
- **Placement**: any (no ClassAd requirements)
- **Host**: 3-node HTCondor cluster
- **Command**: `make hello`
- **Wall-clock**: 1m 51s
- **Jobs**: 4 say_hello + 6 Pegasus infrastructure (stage-in, stage-out, cleanup) = 10 total
- **Notes**: First pipeline run. All 4 greetings produced correctly. Pegasus planning phase ~3s. DAGMan + negotiation overhead dominates for trivial jobs.

### 2026-06-20 — Minipipeline (5+1 fan-out/fan-in, any placement)
- **Workflow**: `workflows/02_minipipeline.py`
- **Placement**: any
- **Host**: 3-node HTCondor cluster
- **Command**: `make minipipeline`
- **Wall-clock**: 1m 56s
- **Jobs**: 5 generate_and_analyse + 1 summarise + 8 infrastructure = 14 total
- **Notes**: Fan-out/fan-in DAG. summary.json produced with correct 5 samples (15,872 total bytes). SHA-256 hashes differ from run to run (random data).

### 2026-06-20 — IoT pipeline (10 devices x 10K readings, any placement)
- **Workflow**: `workflows/04_iot_pipeline.py --placement any`
- **Placement**: any (jobs run on any available node)
- **Host**: 3-node HTCondor cluster
- **Wall-clock**: 2m 41s
- **Cumulative job wall time**: 1m 32s (actual compute via kickstart)
- **Jobs**: 31 compute (10 simulate + 10 preprocess + 10 stats + 1 aggregate) + 14 infrastructure = 45 total
- **Output**: 10 devices, 98,015 clean readings, 1,326 anomalies (1.33%)
- **Notes**: Output matches Nextflow and StreamFlow exactly (same random seed, same algorithm). Actual compute time (1m 32s) vs wall time (2m 41s) shows ~1m overhead from DAGMan polling, negotiation, and condorio file transfers.

### 2026-06-20 — IoT pipeline (10 devices x 10K, continuum placement)
- **Workflow**: `workflows/04_iot_pipeline.py --placement continuum`
- **Placement**: edge jobs on pegasus-edge (ContinuumTier=="edge"), aggregate on pegasus-cloud (ContinuumTier=="cloud")
- **Host**: 3-node HTCondor cluster
- **Wall-clock**: 2m 51s
- **Cumulative job wall time**: 1m 31s
- **Notes**: Continuum placement adds ~10s wall-clock vs "any" placement. Compute time is identical (1m 31s vs 1m 32s), so the extra time comes from constrained matchmaking — fewer eligible slots means longer negotiation waits. Edge jobs ran on the 2-vCPU node, cloud aggregate on the 4-vCPU node.

### 2026-06-20 — IoT pipeline (10 devices x 10K, cloud-only placement)
- **Workflow**: `workflows/04_iot_pipeline.py --placement cloud`
- **Placement**: all jobs on pegasus-cloud (ContinuumTier=="cloud")
- **Host**: 3-node HTCondor cluster
- **Wall-clock**: 2m 31s
- **Cumulative job wall time**: 1m 32s
- **Notes**: Cloud-only is 10s faster than "any" and 20s faster than "continuum". All jobs run on the 4-vCPU node with more resources. Single-node execution eliminates cross-node file transfer overhead via condorio.

---

## Observations

**Pegasus execution model vs Nextflow and StreamFlow:**
- Pegasus uses a **multi-layer architecture**: Python API → `pegasus-plan` (generates DAG) → DAGMan (manages execution) → HTCondor (schedules jobs). Each layer adds overhead.
- The DAGMan polling interval and NEGOTIATOR_INTERVAL (20s) create scheduling latency between jobs. Compute time (1m 32s) is less than half the wall time (2m 41s).
- Pegasus adds **infrastructure jobs** (stage-in, stage-out, cleanup, registration) around user jobs. The IoT pipeline has 31 compute jobs but 45 total (14 infrastructure).
- **condorio** routes all file transfers through the submit node. For 10 devices this is fine; at 50+ devices the 2-vCPU submit node would bottleneck.

**Placement impact (real distributed hardware):**

| Placement | Wall-clock | Compute time | Overhead | Notes |
|-----------|-----------|-------------|----------|-------|
| any | 2m 41s | 1m 32s | 1m 09s | Jobs spread across both nodes |
| continuum | 2m 51s | 1m 31s | 1m 20s | Edge on 2-vCPU, cloud on 4-vCPU |
| cloud-only | 2m 31s | 1m 32s | 59s | All on 4-vCPU node, no cross-node transfers |

Key finding: placement impact is small (~20s) because the bottleneck is DAGMan/negotiation overhead, not compute or data transfer. Compute time is constant across all placements.

**Comparison with local SWMSs (Nextflow/StreamFlow):**
- Pegasus wall times (2m 31s – 2m 51s) are much longer than Nextflow (~1s compute) and StreamFlow (~24s) for the same workload. This is expected — Pegasus is designed for grid-scale distributed computing, not single-machine speed.
- The value of Pegasus is in its **scheduling infrastructure**: ClassAd-based placement, condorio file staging, DAGMan fault tolerance, and workflow provenance tracking via Stampede DB.
- The 31-job DAG (Pegasus/Nextflow) vs 12-job DAG (StreamFlow) affects scheduling overhead linearly. StreamFlow's merged edge stages reduce the number of scheduling rounds.

**HTCondor-specific findings:**
- NEGOTIATOR_INTERVAL=20s is the dominant source of latency between job stages. Each DAG stage waits up to 20s for the negotiator to match jobs to slots.
- `condor_reschedule` after submission triggers immediate negotiation, reducing the first-job latency.
- The ContinuumTier ClassAd works correctly for placement targeting — verified via `condor_history -af RemoteHost`.
- IDTOKENS auth with `security:recommended` (FS + IDTOKENS) works cleanly. Pool signing key + per-node tokens is production-ready.

---

## Cross-SWMS comparison

| Workflow | SWMS | Deployment | Host | Wall-clock | Jobs | Notes |
|----------|------|-----------|------|-----------|------|-------|
| Hello (4 tasks) | Pegasus | HTCondor (any) | 3-node VM cluster | 1m 51s | 10 | 4 compute + 6 infra |
| Minipipeline (5+1) | Pegasus | HTCondor (any) | 3-node VM cluster | 1m 56s | 14 | 5+1 compute + 8 infra |
| IoT (10x10K) | Pegasus | HTCondor (any) | 3-node VM cluster | 2m 41s | 45 | 31 compute + 14 infra |
| IoT (10x10K) | Pegasus | HTCondor (continuum) | 3-node VM cluster | 2m 51s | 45 | edge→edge, cloud→cloud |
| IoT (10x10K) | Pegasus | HTCondor (cloud-only) | 3-node VM cluster | 2m 31s | 45 | all on 4-vCPU cloud |
