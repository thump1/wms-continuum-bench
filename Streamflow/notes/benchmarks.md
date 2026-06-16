# Benchmark notes — StreamFlow

Free-form log of observations and measurements during the StreamFlow POC.
The structured data here will eventually feed comparative tables in the thesis (Nextflow vs. StreamFlow, etc.).

## Run log

For each meaningful run, copy the template below and fill it in.

### Template

```
Date:        YYYY-MM-DD HH:MM
Workflow:    workflows/XX_name.cwl
Deployment:  streamflow-XXX.yml (local / docker / ssh / hybrid)
Host:        Mac M? / Ubuntu server / hybrid
Cores avail: X
RAM avail:   Y GB
Command:     make <target>
Wall-clock:  m:ss
Notes:       observations, errors, surprises
```

---

## Runs

### 2026-06-16 — hello world (local, no container)
- **Workflow**: `workflows/00_hello.cwl`
- **Deployment**: `streamflow-hello.yml` (local)
- **Host**: Mac M3 Pro, 18 GB
- **Command**: `make hello`
- **Wall-clock**: 2.7s
- **Tasks**: 4 scatter (Eduardo, Katja, Salvador, Pedro)
- **Notes**: Purely local execution, no Docker. StreamFlow overhead ~2.5s for engine startup + CWL resolution.

### 2026-06-16 — hello world (Docker ubuntu:24.04)
- **Workflow**: `workflows/01_hello_docker.cwl`
- **Deployment**: `streamflow-hello-docker.yml` (Docker ubuntu:24.04)
- **Host**: Mac M3 Pro, 18 GB, Docker Desktop
- **Command**: `make hello-docker`
- **Wall-clock**: 7.5s
- **Tasks**: 4 scatter (same names)
- **Notes**: Persistent container model — StreamFlow starts one container, runs all tasks via `docker exec`, then tears down. Container deploy+undeploy adds ~5s vs local. Kernel: 6.10.14-linuxkit.

### 2026-06-16 — minipipeline fan-out/fan-in (Docker python:3.12)
- **Workflow**: `workflows/02_minipipeline.cwl`
- **Deployment**: `streamflow-minipipeline.yml` (Docker python:3.12)
- **Host**: Mac M3 Pro, 18 GB, Docker Desktop
- **Command**: `make minipipeline`
- **Wall-clock**: 15.2s
- **Tasks**: 5 generate_and_analyse (scatter) + 1 summarise = 6 CWL jobs
- **Notes**: Uses merged `generate_and_analyse.cwl` tool (workaround for chained-scatter bug). Each scattered job generates random data + computes SHA-256 stats in a single Python step. Gather serialises one-at-a-time due to StreamFlow's sequential gather implementation.

### 2026-06-16 — IoT continuum pipeline (Docker python:3.12, 10 devices × 10K readings)
- **Workflow**: `workflows/04_iot_pipeline.cwl`
- **Deployment**: `streamflow-iot.yml` (Docker python:3.12)
- **Host**: Mac M3 Pro, 18 GB, Docker Desktop
- **Command**: `make iot`
- **Wall-clock**: 29.6s
- **Tasks**: 1 generate_device_ids (ExpressionTool) + 10 device_pipeline (scatter) + 1 cloud_aggregate = 12 CWL jobs
- **Total readings**: 100K (98,015 clean + 1,326 anomalies = 1.33% detected)
- **Notes**: Each `device_pipeline` job runs simulate+preprocess+stats in a single Python heredoc (~2-3s per device). Sequential execution within the scatter (StreamFlow 0.1.6 runs scattered jobs one-at-a-time in Docker). Cloud aggregate produces valid JSON report with per-device and cross-device statistics.

### 2026-06-16 — IoT pipeline on k8s/k3d (Helm3, all on cloud worker)
- **Workflow**: `workflows/04_iot_pipeline.cwl`
- **Deployment**: `streamflow-iot-k8s.yml` (Helm3, both steps → cloud-worker)
- **Host**: Mac M3 Pro, 18 GB — k3d cluster (1 server + 2 agents)
- **Command**: `make iot-k8s`
- **Wall-clock**: 24.6s
- **Notes**: StreamFlow deploys a Helm chart with cloud+edge pods, then execs into them via k8s API. Both device_pipeline and cloud_aggregate bound to `cloud-worker` on the cloud node. ~5s faster than Docker (no per-task container lifecycle).

### 2026-06-16 — IoT pipeline on k8s/k3d (Helm3, continuum: edge+cloud)
- **Workflow**: `workflows/04_iot_pipeline.cwl`
- **Deployment**: `streamflow-iot-k8s-continuum.yml` (device_pipeline → edge-worker, cloud_aggregate → cloud-worker)
- **Host**: Mac M3 Pro, 18 GB — k3d cluster
- **Command**: `make iot-k8s-continuum`
- **Wall-clock**: 24.2s
- **Notes**: True continuum placement — device_pipeline runs on edge node (k3d-continuum-agent-1), cloud_aggregate on cloud node (k3d-continuum-agent-0). Same CWL, different YAML. Performance comparable to all-cloud because data transfer is local (same Docker network).

### 2026-06-16 — IoT pipeline on k8s/k3d (Helm3, cloud-only, no edge pod)
- **Workflow**: `workflows/04_iot_pipeline.cwl`
- **Deployment**: `streamflow-iot-k8s-cloud-only.yml` (Helm3 with edge.enabled=false)
- **Host**: Mac M3 Pro, 18 GB — k3d cluster
- **Command**: `make iot-k8s-cloud-only`
- **Wall-clock**: 23.6s
- **Notes**: Only cloud pod deployed. Slightly faster than continuum (no edge pod startup overhead in Helm deploy).

### 2026-06-16 — IoT pipeline on k8s/k3d with simulated WAN latency
- **Workflow**: `workflows/05_iot_pipeline_latency.cwl`
- **Deployment**: `streamflow-iot-k8s-latency.yml` (edge+cloud, configurable transfer_latency_ms)
- **Host**: Mac M3 Pro, 18 GB — k3d cluster

| Latency (ms) | Wall-clock | Per-device overhead | Notes |
|---------------|-----------|---------------------|-------|
| 0             | 23.9s     | 0s                  | Baseline (no simulated delay) |
| 200           | 26.3s     | 0.4s (2 × 200ms)   | Regional WAN |
| 500           | 32.3s     | 1.0s (2 × 500ms)   | Intercontinental |

- **Notes**: Latency is injected as `time.sleep()` in the device_pipeline tool, simulating data transfer delay between IoT→Edge and Edge→Cloud. Each device experiences 2 transfers: raw data in + stats out. With 10 devices running sequentially, 200ms latency adds ~4s total; 500ms adds ~10s. In a parallel execution model the penalty would be only 2×latency (not 10×2×latency), making parallel scheduling critical for latency-sensitive continuum workflows.

### 2026-06-16 — IoT pipeline on k8s/k3d with tc netem (real network latency)
- **Workflow**: `workflows/04_iot_pipeline.cwl`
- **Deployment**: `streamflow-iot-k8s-continuum.yml` (edge+cloud placement)
- **Host**: Mac M3 Pro, 18 GB — k3d cluster
- **Method**: `tc netem` injected on edge node (k3d-continuum-agent-1) via Alpine sidecar sharing the node's network namespace. Affects ALL packets: k8s API calls, WebSocket exec, pod health checks, data transfers.

| netem delay | Wall-clock | Status  | Notes |
|-------------|-----------|---------|-------|
| 0ms         | 2m 38s    | OK      | Baseline with netem qdisc active (no actual delay) |
| 50ms        | 1m 43s    | OK (retry) | First attempt: WSServerHandshakeError 500. Retry succeeded. |
| 200ms       | 2m 53s    | OK      | Regional WAN simulation |
| 500ms       | ~1m 12s   | FAILED  | WSServerHandshakeError 500 on gather phase — k8s exec API cannot complete WebSocket handshake |

- **Key finding**: tc netem affects the k8s control plane, not just data transfers. Even 0ms netem (qdisc active but no delay) takes 2m 38s vs 24s without netem — a **6.6× slowdown** caused by the netem kernel module intercepting every packet on the node's eth0. This is fundamentally different from sleep-based simulation, which only delays application-level transfers.

**Sleep-based vs tc netem comparison:**

| Latency | Sleep-based | tc netem | Ratio |
|---------|------------|----------|-------|
| 0ms     | 23.9s      | 2m 38s   | 6.6×  |
| 200ms   | 26.3s      | 2m 53s   | 6.6×  |
| 500ms   | 32.3s      | FAILED   | —     |

- **Implication**: Sleep-based simulation is useful for modelling application-level data transfer costs in isolation. tc netem captures the full system impact (control plane + data plane) but becomes destructive at high latencies because the SWMS's orchestration protocol (WebSocket exec) shares the same degraded network path. In a real edge-cloud deployment, the control plane would typically use a separate management network — making tc netem's impact pessimistic but revealing of a real coupling risk.

---

## Observations

**StreamFlow execution model vs Nextflow:**
- StreamFlow uses a **persistent container** (`docker run --detach` then `docker exec` per job). Nextflow creates a fresh container per task.
- StreamFlow's scatter execution in Docker appears **sequential** (one scattered job finishes before the next starts). Nextflow parallelises scattered tasks up to the available CPU slots.
- StreamFlow's gather phase is also sequential — each gather token is processed one at a time with ~400ms latency per token (container round-trip overhead). This adds noticeable overhead for large scatter arrays.
- StreamFlow does not expose per-task CPU/RSS metrics in its output. Nextflow's `-with-trace` provides CPU%, RSS, I/O per task.

**Implications for thesis:**
- For the **same** IoT pipeline (10×10K), Nextflow's per-stage realtimes sum to ~1s total compute; StreamFlow takes ~29.6s wall-clock (Docker) / ~24s (k8s). The difference is engine overhead (CWL resolution, sequential scatter, serial gather).
- The persistent-container model is advantageous for **long-running tasks** (no per-task startup), but disadvantageous for **many short tasks** (serialisation + gather overhead dominates).
- StreamFlow's real value is in **cross-environment deployment** (the YAML-based model→binding decoupling), not raw single-node performance.

**k8s/continuum findings:**
- **Same CWL, 5 deployment targets**: local, Docker, SSH, k8s-cloud, k8s-continuum. Only the YAML changes. This validates StreamFlow's core thesis: workflow portability across the continuum.
- **Placement has negligible impact in a local cluster** (24.2s continuum vs 23.6s cloud-only). On a real WAN-separated continuum, the difference would be dominated by data transfer latency.
- **Latency scales linearly with sequential scatter**: 200ms per-transfer × 2 transfers × 10 devices (sequential) = ~4s overhead. This is a strong argument for parallel scatter execution — in Nextflow's k8s mode, latency would only add 2×200ms = 0.4s (parallelised across devices).
- **StreamFlow's Helm3 connector** is production-quality: manages chart lifecycle, schedules on labeled nodes, handles cross-pod data transfer. No k8s-specific code needed in the CWL.

**tc netem findings:**
- **Control plane coupling**: tc netem on a k8s node degrades the orchestration protocol (WebSocket exec) alongside data transfers. This coupling is absent in sleep-based simulation and exposes a real architectural concern for edge-cloud SWMSs that use the same network path for control and data.
- **Nonlinear failure**: 500ms netem causes WebSocket handshake failures (HTTP 500). The k8s API server has internal timeouts that interact with network latency in unpredictable ways. At 50ms there were intermittent failures (succeeded on retry).
- **Baseline overhead**: Even 0ms netem adds ~130s overhead (2m38s vs 24s). The netem kernel qdisc module introduces packet-processing overhead even with zero configured delay, plus it enables per-packet timestamping.
- **Thesis implication**: Real edge-cloud SWMS deployments need a **separate management plane** (out-of-band control network) to avoid control/data coupling. This validates the observation in SoA §5 about SDN/NFV providing network slicing for heterogeneous traffic classes.

---

## Cross-SWMS comparison

See also `SWMS-POC/Nextflow/notes/benchmarks.md` for the Nextflow baseline.

| Workflow            | SWMS       | Deployment      | Host    | Wall-clock | Notes |
|---------------------|------------|-----------------|---------|------------|-------|
| Hello (4 tasks)     | StreamFlow | local           | Mac M3  | 2.7s       | No containers |
| Hello (4 tasks)     | StreamFlow | docker (ubuntu)  | Mac M3  | 7.5s       | Persistent container |
| Mini-pipeline (5 s) | StreamFlow | docker (python)  | Mac M3  | 15.2s      | Merged tool, sequential scatter |
| IoT (10×10K)        | Nextflow   | docker           | Mac M3  | —          | Per-stage: simulate 80ms, preprocess 784ms, stats 84ms, agg 70ms |
| IoT (10×10K)        | StreamFlow | docker (python)  | Mac M3  | 29.6s      | Sequential scatter, serial gather |
| IoT (10×10K)        | StreamFlow | k8s all-cloud    | Mac M3  | 24.6s      | Helm3, both steps on cloud pod |
| IoT (10×10K)        | StreamFlow | k8s continuum    | Mac M3  | 24.2s      | Edge on edge node, cloud on cloud node |
| IoT (10×10K)        | StreamFlow | k8s cloud-only   | Mac M3  | 23.6s      | Single cloud pod, no edge |
| IoT (10×10K)        | StreamFlow | k8s latency 200ms| Mac M3  | 26.3s      | Edge+cloud + 200ms simulated WAN |
| IoT (10×10K)        | StreamFlow | k8s latency 500ms| Mac M3  | 32.3s      | Edge+cloud + 500ms simulated WAN |
| IoT (10×10K)        | StreamFlow | k8s netem 0ms    | Mac M3  | 2m 38s     | tc netem on edge node, no delay |
| IoT (10×10K)        | StreamFlow | k8s netem 50ms   | Mac M3  | 1m 43s     | tc netem 50ms (retry after WS 500) |
| IoT (10×10K)        | StreamFlow | k8s netem 200ms  | Mac M3  | 2m 53s     | tc netem 200ms regional WAN |
| IoT (10×10K)        | StreamFlow | k8s netem 500ms  | Mac M3  | FAILED     | WS handshake error — k8s API broke |
| IoT (50×100K)       | Nextflow   | docker           | Mac M3  | 7m 37s     | 151 tasks, ~10-12 concurrent |
| IoT (50×100K)       | Nextflow   | k8s (k3d)       | Mac M3  | 1m 55s     | ~33 concurrent pods, over-subscribed |
| IoT (10×10K)        | StreamFlow | ssh              | Ubuntu  | —          | (pending: server credentials) |
| IoT (10×10K)        | StreamFlow | hybrid           | Mac+Ubu | —          | (pending: server credentials) |
