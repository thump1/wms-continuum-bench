# Cross-SWMS Comparative Benchmarks

Consolidated benchmark data across all SWMS proof-of-concept evaluations. All runs on the same hardware (Mac M3 Pro, 18 GB) unless otherwise noted. Data from `Nextflow/notes/benchmarks.md` and `StreamFlow/notes/benchmarks.md`.

## Hardware

| Resource | Specification |
|----------|--------------|
| CPU | Apple M3 Pro (11 cores: 5P + 6E) |
| RAM | 18 GB unified |
| Disk | ~500 GB NVMe (APFS) |
| Docker | Docker Desktop for Mac (Linux kernel 6.10.14-linuxkit) |
| k3d cluster | 3 nodes: 1 server + 2 agents (cloud + edge), shared Docker network |

## 1. Simple pipelines

| Pipeline | SWMS | Deployment | Wall-clock | Tasks | Notes |
|----------|------|-----------|-----------|-------|-------|
| Hello (4 names) | Nextflow | local (no container) | <1s | 4 | Groovy DSL, channel-based |
| Hello (4 names) | StreamFlow | local (no container) | 2.7s | 4 | CWL + engine startup overhead |
| Hello (4 names) | Nextflow | Docker (ubuntu:24.04) | ~3s | 4 | Per-task container |
| Hello (4 names) | StreamFlow | Docker (ubuntu:24.04) | 7.5s | 4 | Persistent container, `docker exec` |
| Minipipeline (5+1) | Nextflow | Docker (python:3.12) | ~5s | 11 | 5 generate + 5 analyse + 1 summarise |
| Minipipeline (5+1) | StreamFlow | Docker (python:3.12) | 15.2s | 6 | Merged tool (chained-scatter bug workaround) |

**Takeaway**: Nextflow has lower engine overhead (~0.5s vs ~2.5s) and runs scatter jobs in parallel. StreamFlow's sequential scatter and CWL resolution add latency for short-lived tasks. For pipelines under 10s of compute, engine overhead dominates.

## 2. IoT continuum pipeline (10 devices x 10K readings)

Identical scientific workload: simulate IoT sensors, edge preprocessing (z-score anomaly detection), edge statistics, cloud aggregation. 100K total readings.

| SWMS | Deployment | Wall-clock | Scatter model | Notes |
|------|-----------|-----------|---------------|-------|
| Nextflow | Docker | ~1s compute | Parallel (10 concurrent) | Per-stage: simulate 80ms, preprocess 784ms, stats 84ms, agg 70ms |
| StreamFlow | Docker | 29.6s | Sequential | Persistent container, serial gather |
| StreamFlow | k8s all-cloud | 24.6s | Sequential | Helm3, both steps on cloud pod |
| StreamFlow | k8s continuum | 24.2s | Sequential | Edge on edge node, cloud on cloud |
| StreamFlow | k8s cloud-only | 23.6s | Sequential | Single cloud pod |

**Takeaway**: Nextflow finishes the actual computation in ~1s (parallel scatter across all 10 devices). StreamFlow takes 24-30s because it runs scattered jobs sequentially. The k8s executor is slightly faster than Docker for StreamFlow because it avoids per-exec container lifecycle overhead (persistent Helm-deployed pods).

## 3. IoT continuum pipeline (50 devices x 100K readings)

Scale test: 5M total readings, 151 tasks.

| SWMS | Deployment | Wall-clock | Concurrent tasks | EDGE_PREPROCESS avg |
|------|-----------|-----------|-----------------|---------------------|
| Nextflow | Docker | 7m 37s | ~10-12 | 7.5s |
| Nextflow | Native (no container) | 7m 44s | ~10-12 | 8.5s |
| Nextflow | k8s (k3d) | 1m 55s | ~33 | 35s |

**Takeaway**: k8s is 4x faster wall-clock despite 5x slower per-task execution, because it over-subscribes CPU (~33 concurrent pods vs ~11 local tasks). Container vs native overhead is <2% for CPU-bound workloads.

StreamFlow was not tested at this scale (50x100K) because sequential scatter would take ~25min+ (extrapolated from 10x10K sequential timing).

## 4. Latency experiments (StreamFlow k8s, 10 devices x 10K)

### 4a. Sleep-based simulation (application-level delay)

Simulates WAN transfer latency with `time.sleep()` in the CWL tool. Only delays data transfers, not control plane.

| Latency | Wall-clock | Overhead vs baseline | Per-device overhead |
|---------|-----------|---------------------|---------------------|
| 0ms | 23.9s | baseline | 0s |
| 200ms | 26.3s | +2.4s (+10%) | 0.4s (2 x 200ms) |
| 500ms | 32.3s | +8.4s (+35%) | 1.0s (2 x 500ms) |

Overhead scales linearly: each device has 2 transfer points (IoT-to-Edge, Edge-to-Cloud). With sequential scatter, total overhead = `latency x 2 x num_devices`.

### 4b. tc netem (real network-level delay)

Injects packet delay on the k3d edge node via `tc netem`. Affects ALL traffic: k8s API, WebSocket exec, health checks, data transfers.

| Latency | Wall-clock | Status | Notes |
|---------|-----------|--------|-------|
| 0ms | 2m 38s | OK | netem qdisc active, no configured delay |
| 50ms | 1m 43s | OK (retry) | First attempt: WebSocket 500 error |
| 200ms | 2m 53s | OK | Regional WAN |
| 500ms | ~1m 12s | FAILED | k8s exec API WebSocket handshake broken |

### 4c. Sleep vs netem comparison

| Latency | Sleep-based | tc netem | Slowdown factor |
|---------|------------|----------|-----------------|
| 0ms | 23.9s | 2m 38s (158s) | 6.6x |
| 200ms | 26.3s | 2m 53s (173s) | 6.6x |
| 500ms | 32.3s | FAILED | -- |

**Key finding**: tc netem is 6.6x slower than sleep-based simulation even at 0ms delay. The netem kernel module intercepts every packet on the node's network interface, affecting the k8s orchestration protocol (WebSocket-based `kubectl exec`). At 500ms, the WebSocket handshake fails entirely.

**Implication for edge-cloud SWMS architectures**: Real network latency degrades the control plane alongside data transfers. SWMSs that use in-band orchestration (same network path for control and data) are vulnerable to latency-induced control plane failures. This motivates separate management networks (SDN/NFV network slicing) for production edge-cloud deployments.

## 5. Pegasus WMS (HTCondor cluster, 10 devices x 10K readings)

First SWMS evaluated on real distributed hardware: 3-node HTCondor cluster on VMware VMs (Ryzen 7-3700X, 64 GB host). CM/submit (2 vCPU, 3.3 GB), cloud executor (4 vCPU, 15 GB), edge executor (2 vCPU, 7.2 GB). All Ubuntu 26.04, HTCondor 25.11.0, Pegasus 5.1.2.

| Pipeline | Placement | Wall-clock | Compute time | Jobs (compute+infra) | Notes |
|----------|-----------|-----------|-------------|---------------------|-------|
| Hello (4 tasks) | any | 1m 51s | — | 4+6=10 | DAGMan overhead dominates |
| Minipipeline (5+1) | any | 1m 56s | — | 6+8=14 | Fan-out/fan-in DAG |
| IoT (10x10K) | any | 2m 41s | 1m 32s | 31+14=45 | Jobs spread across both nodes |
| IoT (10x10K) | continuum | 2m 51s | 1m 31s | 31+14=45 | Edge on 2-vCPU, cloud on 4-vCPU |
| IoT (10x10K) | cloud-only | 2m 31s | 1m 32s | 31+14=45 | All on 4-vCPU node |

**Takeaway**: Pegasus wall times are dominated by scheduling overhead (DAGMan polling, NEGOTIATOR_INTERVAL=20s, condorio file transfers), not compute. Actual compute time is constant (~1m 32s) across all placements. The 31-job modular DAG means more scheduling rounds than StreamFlow's 12-job merged design. Placement impact is small (~20s) because negotiation latency, not data transfer, is the bottleneck at this scale.

## 6. Architectural comparison

| Dimension | Nextflow | StreamFlow | Pegasus |
|-----------|----------|------------|---------|
| **Workflow language** | Nextflow DSL (Groovy) | CWL (YAML standard) | Python API |
| **Scheduler** | Built-in | Built-in | HTCondor (external) |
| **Scatter execution** | Parallel (up to CPU limit) | Sequential (v0.1.6) | Parallel (HTCondor slots) |
| **Container model** | Per-task container | Persistent container (`docker exec`) | No containers (bare-metal) |
| **k8s integration** | Native executor (pod per task) | Helm3 connector (persistent pods) | Condor-CE / glide-in |
| **Multi-site deployment** | Custom executor plugins | Native YAML bindings | HTCondor ClassAd matching |
| **Continuum support** | Limited (single executor) | Native (per-step binding) | ContinuumTier ClassAd |
| **Data staging** | Work dir / publishDir | StreamFlow runtime | condorio (HTCondor file transfer) |
| **Observability** | `-with-trace` (CPU, RSS, I/O) | SQLite provenance DB | Stampede DB + kickstart records |
| **DAG shape (IoT 10x)** | 31 jobs (4-stage) | 12 jobs (merged edge) | 31 jobs (4-stage) + 14 infra |
| **Maturity** | Production (Seqera Labs) | Research (Univ. Torino, v0.1.6) | Production (USC ISI, v5.1.2) |

## 7. Scheduling insights

### Sequential vs parallel scatter

StreamFlow's sequential scatter is its main performance bottleneck for multi-device workloads:

| Scale | StreamFlow (sequential) | Nextflow (parallel) | Ratio |
|-------|------------------------|--------------------:|------:|
| 10 devices x 10K | 24.2s | ~1s compute | ~24x |
| 50 devices x 100K | ~25min (est.) | 1m 55s (k8s) | ~13x |

The gap narrows at scale because Nextflow's local executor also serialises beyond its CPU limit (~11 tasks). In k8s, Nextflow over-subscribes and achieves higher concurrency.

### Placement impact — StreamFlow (local k3d cluster)

| StreamFlow config | Wall-clock | Delta vs cloud-only |
|-------------------|-----------|---------------------|
| Cloud-only (1 pod) | 23.6s | baseline |
| Continuum (edge + cloud) | 24.2s | +0.6s (+2.5%) |
| All-on-cloud (2 pods) | 24.6s | +1.0s (+4.2%) |

Placement has negligible impact in a local cluster (shared Docker network, zero real latency). The slight overhead of multi-pod configs comes from Helm chart deployment of additional pods. In a real WAN-separated continuum, placement would dominate due to data transfer costs.

### Placement impact — Pegasus (real distributed cluster)

| Pegasus config | Wall-clock | Compute time | Delta vs cloud-only |
|----------------|-----------|-------------|---------------------|
| Cloud-only (4 vCPU) | 2m 31s | 1m 32s | baseline |
| Any (both nodes) | 2m 41s | 1m 32s | +10s (+6.6%) |
| Continuum (edge+cloud) | 2m 51s | 1m 31s | +20s (+13.2%) |

On real distributed hardware, continuum placement adds ~20s overhead. Unlike the local k3d cluster, this overhead is real (cross-node condorio file transfers + constrained matchmaking). But compute time is identical — the bottleneck is scheduling infrastructure, not compute or data transfer at this scale.

### Latency sensitivity

For sequential scatter with N devices and L ms latency per transfer:
- **Total overhead** = N x 2 x L (sleep-based, application-level)
- **Parallel scatter** would reduce this to 2 x L regardless of N

This makes parallel scheduling critical for latency-sensitive continuum workflows. A 200ms regional WAN latency adds 4s to a 10-device sequential pipeline but only 0.4s to a parallel one.

## 8. Pending comparisons

| SWMS | Status | Next step |
|------|--------|-----------|
| Nextflow | Complete (local + Docker + k8s) | SSH to Ubuntu server |
| StreamFlow | Complete (local + Docker + k8s + latency) | SSH/hybrid to Ubuntu server |
| Pegasus | Complete (3-node HTCondor cluster) | Scale tests (50x100K) |
| K3s multi-node | Not started | Deploy on Windows VMs |
