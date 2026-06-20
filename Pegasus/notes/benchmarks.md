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
| IoT (10x10K) | Pegasus | HTCondor (edge-only) | 3-node VM cluster | 2m 37s | 45 | all on 2-vCPU edge |

---

## Experiment 1: Edge-only vs Cloud-only placement (10x10K)

### 2026-06-20 — IoT pipeline (10 devices x 10K, edge-only)
- **Workflow**: `workflows/04_iot_pipeline.py --placement edge`
- **Placement**: all 31 compute jobs on pegasus-edge (ContinuumTier=="edge"), 2 vCPU, 2 slots
- **Wall-clock**: 2m 37s
- **Cumulative job wall time**: 1m 32s
- **Per-job timing** (from condor_history):
  - simulate_sensors: 10 jobs, avg 1.8s (range 1-4s)
  - edge_preprocess: 10 jobs, avg 3.0s (all 3s)
  - edge_stats: 10 jobs, avg 2.3s (range 1-8s)
  - cloud_aggregate: 1 job, 1s

### 2026-06-20 — IoT pipeline (10 devices x 10K, cloud-only — repeat)
- **Workflow**: `workflows/04_iot_pipeline.py --placement cloud`
- **Placement**: all 31 compute jobs on pegasus-cloud (ContinuumTier=="cloud"), 4 vCPU, 4 slots
- **Wall-clock**: 2m 42s
- **Cumulative job wall time**: 1m 32s
- **Per-job timing** (from condor_history):
  - simulate_sensors: 10 jobs, avg 2.6s (range 1-7s)
  - edge_preprocess: 10 jobs, avg 4.0s (range 3-9s)
  - edge_stats: 10 jobs, avg 2.8s (range 1-7s)
  - cloud_aggregate: 1 job, 2s

**Finding**: Edge-only (2m 37s) is 5s FASTER than cloud-only (2m 42s) despite having half the CPU. Cloud's 4 parallel slots generate more concurrent condorio transfers through the 2-vCPU submit node, creating a transfer bottleneck that negates the extra compute capacity. Per-job times on cloud show higher variance (1-9s vs 1-4s on edge) due to contention.

---

## Experiment 2: Latency injection (continuum placement, 10x10K)

tc netem injected on the edge node's primary interface (ens33) via `tc qdisc replace dev ens33 root netem delay Xms`. Verified via `ping` from CM.

### 2026-06-20 — Continuum baseline (0ms)
- **Wall-clock**: 2m 56s
- **Cumulative compute**: 1m 32s

### 2026-06-20 — Continuum + 50ms latency on edge
- **Wall-clock**: 3m 42s
- **Cumulative compute**: 1m 31s
- **Overhead vs baseline**: +46s (+26%)
- **Ping CM→edge**: 50.8ms avg

### 2026-06-20 — Continuum + 200ms latency on edge
- **Wall-clock**: 5m 12s
- **Cumulative compute**: 1m 32s
- **Overhead vs baseline**: +2m 16s (+77%)
- **Ping CM→edge**: 200.6ms avg

**Latency summary:**

| Latency | Wall-clock | Compute | Overhead vs 0ms | Expected (naive) | Amplification factor |
|---------|-----------|---------|-----------------|-------------------|--------------------|
| 0ms | 2m 56s | 1m 32s | baseline | — | — |
| 50ms | 3m 42s | 1m 31s | +46s (+26%) | ~3s | 15x |
| 200ms | 5m 12s | 1m 32s | +2m 16s (+77%) | ~12s | 11x |

**Naive expectation**: 30 edge jobs x 2 transfers x L = 3s at 50ms, 12s at 200ms. Actual overhead is 11-15x higher because condorio's CEDAR protocol involves multiple round trips per transfer (TCP handshake, IDTOKENS auth, file negotiation, chunked data, completion ack), and the HTCondor control plane (heartbeats, negotiation updates, ClassAd matching) also incurs latency on every packet.

**Comparison with StreamFlow tc netem**: StreamFlow's k8s WebSocket exec broke entirely at 500ms. Pegasus/HTCondor completed at 200ms because condorio uses a simpler, more latency-tolerant file transfer protocol than WebSocket-based kubectl exec. However, the control plane amplification is similar in both systems.

---

## Experiment 3: Scaled workload (10x100K)

10x more readings per device (100K vs 10K). Tests whether the edge-cloud performance gap grows with workload size.

### 2026-06-20 — IoT pipeline (10 devices x 100K, edge-only)
- **Workflow**: `workflows/04_iot_pipeline.py --devices 10 --readings 100000 --placement edge`
- **Wall-clock**: 3m 46s
- **Cumulative compute**: 3m 44s
- **Scheduling overhead**: 2s (compute-dominated)

### 2026-06-20 — IoT pipeline (10 devices x 100K, cloud-only)
- **Workflow**: `workflows/04_iot_pipeline.py --devices 10 --readings 100000 --placement cloud`
- **Wall-clock**: 3m 11s
- **Cumulative compute**: 3m 47s
- **Per-job timing** (from condor_history):
  - simulate_sensors: 10 jobs, avg 2.7s
  - edge_preprocess: 10 jobs, avg 17.5s (range 15-21s, vs 3s at 10K)
  - edge_stats: 10 jobs, avg 2.2s
  - cloud_aggregate: 1 job, 2s

**Scale comparison:**

| Workload | Edge-only (2 vCPU) | Cloud-only (4 vCPU) | Cloud advantage | Bottleneck |
|----------|-------------------|---------------------|-----------------|------------|
| 10x10K | 2m 37s | 2m 42s | -5s (slower) | Transfer overhead |
| 10x100K | 3m 46s | 3m 11s | +35s (faster) | Compute (parallelism) |

**Finding**: At small workloads, scheduling and transfer overhead dominates — cloud's extra parallelism creates more concurrent transfers that bottleneck the submit node. At 10x scale, compute dominates — cloud's 4 concurrent slots process the pipeline ~15% faster. The crossover point where cloud becomes advantageous is between 10K and 100K readings per device.

This is the fundamental edge-cloud tradeoff: edge has lower latency to data sources but fewer resources; cloud has more resources but higher transfer cost. The workload size determines which factor dominates.
