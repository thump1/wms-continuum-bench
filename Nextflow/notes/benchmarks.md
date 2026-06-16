# Benchmark notes — Nextflow

Free-form log of observations and measurements during the Nextflow POC.
The structured data here will eventually feed comparative tables in the thesis (Nextflow vs. Pegasus vs. StreamFlow, etc.).

## Run log

For each meaningful run, copy the template below and fill it in.

### Template

```
Date:        YYYY-MM-DD HH:MM
Pipeline:    pipelines/XX_name.nf
Profile:     standard / docker / server / k8s
Host:        Mac M? / Ubuntu server / VM cluster (3 nodes)
Cores avail: X
RAM avail:   Y GB
Command:     nextflow run pipelines/XX_name.nf -profile XXX
Wall-clock:  m:ss
CPU peak:    %
RSS peak:    MB
Notes:       observations, errors, surprises
```

---

## Runs

### 2026-06-03 — hello world (no container)
- **Pipeline**: `pipelines/00_hello.nf`
- **Profile**: `standard`
- **Host**: Mac M3 Pro, 18 GB, Docker Desktop
- **Command**: `make hello`
- **Notes**: First successful run after fixing Nextflow 26.04 `def` config error.

### 2026-06-03 — hello world (Docker container)
- **Pipeline**: `pipelines/01_hello_docker.nf`
- **Profile**: `docker`
- **Host**: Mac M3 Pro, 18 GB, Docker Desktop
- **Command**: `make hello-docker`
- **Notes**: 4 tasks (Eduardo, Katja, Salvador, Pedro). Containers: ubuntu:24.04. Kernel: 6.10.14-linuxkit.

### 2026-06-03 — minipipeline fan-out/fan-in
- **Pipeline**: `pipelines/02_minipipeline.nf`
- **Profile**: `docker`
- **Host**: Mac M3 Pro, 18 GB, Docker Desktop
- **Command**: `make minipipeline`
- **Notes**: 11 tasks (5 generate + 5 analyse + 1 summarise). All completed.

### 2026-06-03 — benchmark baseline (conservative config)
- **Pipeline**: `pipelines/03_benchmark.nf`
- **Profile**: `docker` (cpus=2, memory=4GB — pre-tuning)
- **Host**: Mac M3 Pro, 18 GB, Docker Desktop
- **Command**: `make benchmark` (10 chunks × 25 MB, 500 hash rounds)
- **Total data**: 250 MB
- **Tasks**: 31 (10 ingest + 10 preprocess + 10 analyze + 1 aggregate)

| Stage | Avg realtime | Avg CPU% | Peak RSS | Bottleneck |
|-------|-------------|----------|----------|------------|
| INGEST | 161 ms | 42% | 5 MB | I/O (dd urandom) |
| PREPROCESS | 774 ms | 78% | 4 MB | CPU+I/O (gzip) |
| ANALYZE | 586 ms | 145% | 3-8 MB | CPU (SHA-256 ×500) |
| AGGREGATE | 10 ms | 0% | 3 MB | trivial |

- **Notes**: Config was cpus=2/task, limiting parallelism to ~5 concurrent tasks on the M3 Pro. All compressed outputs ~26.2 MB (random data is incompressible). Next run: tuned config (cpus=1/task for max parallelism) + bigger dataset.

### 2026-06-03 — benchmark stress test (tuned config)
- **Pipeline**: `pipelines/03_benchmark.nf`
- **Profile**: `docker` (cpus=1, memory=12GB — post-tuning)
- **Host**: Mac M3 Pro, 18 GB, Docker Desktop
- **Command**: `make benchmark CHUNKS=20 CHUNK_MB=100 ROUNDS=2000`
- **Total data**: 2 GB
- **Wall-clock**: 1m 33s
- **Tasks**: 61 (20 ingest + 20 preprocess + 20 analyze + 1 aggregate)

| Stage | Avg realtime | Avg CPU% | Peak RSS | I/O read | I/O write |
|-------|-------------|----------|----------|----------|-----------|
| INGEST | 208 ms | 74.6% | 5 MB | 100 MB | 100 MB |
| PREPROCESS | 2.05 s | 96.8% | 4.3 MB | 100 MB | 100 MB |
| ANALYZE | 1.3 s | 171.4% | 2.9-8.2 MB | 111.5 MB | 394 KB |
| AGGREGATE | 15 ms | 50% | 2.7 MB | 43 KB | 3.6 KB |

**Scaling vs baseline (10×25MB, 500 rounds, cpus=2):**

| Stage | Baseline → Stress | Data ×4, Rounds ×4 | Actual speedup |
|-------|-------------------|---------------------|---------------|
| INGEST | 161 ms → 208 ms | 1.29× slower | Sub-linear: dd scales well |
| PREPROCESS | 774 ms → 2050 ms | 2.65× slower | gzip nearly linear with data size |
| ANALYZE | 586 ms → 1300 ms | 2.22× slower | Hash loop overhead (echo+sha256sum per iteration) |

**Observations:**
- PREPROCESS is the clear bottleneck at ~97% CPU (single-core saturation on gzip).
- ANALYZE shows 171% CPU — sha256sum uses ARM crypto extensions on M3, parallelised internally.
- Memory footprint still tiny (max 8 MB). Pipeline is purely CPU/IO bound.
- cpus=1 config allows ~10-12 concurrent tasks vs ~5 previously — better utilisation of M3 Pro cores.

### 2026-06-03 — IoT pipeline, default (10 devices × 10K readings)
- **Pipeline**: `pipelines/04_iot_pipeline.nf`
- **Profile**: `docker` (cpus=1, memory=12GB)
- **Host**: Mac M3 Pro, 18 GB, Docker Desktop
- **Command**: `make iot` (10 devices × 10,000 readings, 2% anomaly rate)
- **Total readings**: 100K (98,015 clean + 1,326 anomalies = 1.33% detected)
- **Tasks**: 31 (10 simulate + 10 preprocess + 10 stats + 1 aggregate)

| Stage (continuum layer) | Avg realtime | Avg CPU% | Peak RSS |
|-------------------------|-------------|----------|----------|
| SIMULATE_SENSORS (IoT) | 80 ms | 92% | 12 MB |
| EDGE_PREPROCESS (Edge) | 784 ms | 98.6% | 12 MB |
| EDGE_STATS (Edge) | 84 ms | 94.6% | 12 MB |
| CLOUD_AGGREGATE (Cloud) | 70 ms | 82.5% | 12 MB |

### 2026-06-03 — IoT pipeline, stress test (50 devices × 100K readings)
- **Pipeline**: `pipelines/04_iot_pipeline.nf`
- **Profile**: `docker` (cpus=1, memory=12GB)
- **Host**: Mac M3 Pro, 18 GB, Docker Desktop
- **Command**: `make iot DEVICES=50 READINGS=100000`
- **Wall-clock**: 7m 37s
- **Total readings**: 5M (4,901,528 clean + 65,279 anomalies = 1.31% detected)
- **Tasks**: 151 (50 simulate + 50 preprocess + 50 stats + 1 aggregate)

| Stage (continuum layer) | Avg realtime | Avg CPU% | Peak RSS | I/O read | I/O write |
|-------------------------|-------------|----------|----------|----------|-----------|
| SIMULATE_SENSORS (IoT) | 241 ms | 89.7% | 12 MB | 442 KB | 2.6 MB |
| EDGE_PREPROCESS (Edge) | 7.5 s | 99.8% | 50 MB | 3.1 MB | 2.6 MB |
| EDGE_STATS (Edge) | 286 ms | 98.2% | 12 MB | 3.1 MB | 1.6 KB |
| CLOUD_AGGREGATE (Cloud) | 91 ms | 73.3% | 12 MB | 637 KB | 32 KB |

**Scaling analysis (10K → 100K readings per device, 10× data):**

| Stage | 10K → 100K | Multiplier | Complexity |
|-------|-----------|------------|------------|
| SIMULATE_SENSORS | 80 ms → 241 ms | 3.0× | Sub-linear (Python CSV write) |
| EDGE_PREPROCESS | 784 ms → 7.5 s | 9.6× | ~Linear (sliding-window z-score is O(n×w)) |
| EDGE_STATS | 84 ms → 286 ms | 3.4× | Sub-linear (simple aggregation) |

**Observations:**
- **EDGE_PREPROCESS dominates**: 7.5s avg, 99.8% CPU — the z-score sliding window on 100K rows in pure Python is the bottleneck. Realistic for edge nodes without NumPy.
- **Memory pressure appears**: 50 MB per EDGE_PREPROCESS task (100K dicts in Python). With ~10 concurrent tasks = ~500 MB. Still comfortable on 18 GB, but would matter on real edge devices.
- **Container overhead is significant**: ~40s of actual compute, 7m 37s wall-clock. Docker startup + Python interpreter initialization per task dominates. Key thesis insight: container-per-task has a steep fixed cost in the continuum.
- **Anomaly detection is consistent**: 1.31% detected vs 2% injected across both scales. The gap is NaN dropouts filtered before z-score.

### 2026-06-03 — IoT pipeline, NATIVE (50 devices × 100K readings, no containers)
- **Pipeline**: `pipelines/04_iot_pipeline.nf`
- **Profile**: `standard` (no Docker — Python 3.14 on host)
- **Host**: Mac M3 Pro, 18 GB
- **Command**: `make iot-native DEVICES=50 READINGS=100000`
- **Wall-clock**: 7m 44s
- **Tasks**: 151
- **Note**: Nextflow does not collect CPU/RSS metrics on macOS without a container engine. Trace only has second-resolution realtime.

| Stage (continuum layer) | Avg realtime |
|-------------------------|-------------|
| SIMULATE_SENSORS (IoT) | <1 s |
| EDGE_PREPROCESS (Edge) | 8.5 s |
| EDGE_STATS (Edge) | <1 s |
| CLOUD_AGGREGATE (Cloud) | <1 s |

**Docker vs Native comparison (same pipeline, same hardware):**

| Runtime | Wall-clock | EDGE_PREPROCESS avg | Python version |
|---------|-----------|---------------------|---------------|
| Docker | 7m 37s | 7.5 s | 3.12 (container) |
| Native | 7m 44s | 8.5 s | 3.14 (host) |

**Key finding: Docker overhead is negligible (<2%) for CPU-bound workflows.** The earlier estimate of "~40s compute in 7m37s wall-clock" was misleading — the actual bottleneck is the pure Python computation (z-score sliding window), not container startup. Container startup cost is amortised over the 7-10s EDGE_PREPROCESS tasks. The slight native slowdown may be Python 3.14 vs 3.12 regression, or macOS process scheduling differences. Either way, runtime choice only matters for short-lived tasks, not for real scientific workloads.

### 2026-06-03 — IoT pipeline on k3d/k8s (50 devices × 100K readings)
- **Pipeline**: `pipelines/04_iot_pipeline.nf`
- **Profile**: `k8s` (cpus=1, memory=512MB per pod)
- **Host**: Mac M3 Pro, 18 GB — k3d cluster (1 server + 2 agents)
- **Command**: `make iot-k8s DEVICES=50 READINGS=100000`
- **Wall-clock**: 1m 55s
- **Tasks**: 151
- **Concurrency**: ~33 pods simultaneously (k8s scheduled in waves)

| Stage (continuum layer) | Avg realtime | Avg CPU% | Peak RSS |
|-------------------------|-------------|----------|----------|
| SIMULATE_SENSORS (IoT) | 1.2 s | 35% | 16 MB |
| EDGE_PREPROCESS (Edge) | 35 s (range 14-50s) | 50% | 50 MB |
| EDGE_STATS (Edge) | 0.7 s | 72% | 12 MB |
| CLOUD_AGGREGATE (Cloud) | 108 ms | 91% | 11 MB |

**EDGE_PREPROCESS variance**: early tasks (competing with 33 concurrent pods) took 40-50s at ~33% CPU. Later tasks (less contention) took 14-18s at ~80% CPU. This shows k8s CPU scheduling dynamics under resource contention.

---

## Three-way runtime comparison (same pipeline, same hardware)

| Metric | Docker | Native | k8s (k3d) |
|--------|--------|--------|-----------|
| **Wall-clock** | **7m 37s** | **7m 44s** | **1m 55s** |
| EDGE_PREPROCESS avg realtime | 7.5 s | 8.5 s | 35 s |
| EDGE_PREPROCESS avg CPU% | 99.8% | N/A | 50% |
| Concurrent tasks | ~10-12 | ~10-12 | ~33 |
| Peak RSS per task | 50 MB | N/A | 50 MB |
| Scheduling model | local (1 task:1 CPU) | local (1 task:1 CPU) | k8s (resource requests) |

**Key finding: k8s is 4× faster wall-clock despite 5× slower per-task execution.**

Why? The local executor enforces strict 1:1 CPU mapping (cpus=1 per task, ~11 cores = ~11 concurrent tasks). k8s over-subscribes CPU by scheduling ~33 pods on the same 11 cores. Each task gets ~50% CPU (slower individually), but 3× more tasks run simultaneously. For this I/O-mixed workload, over-subscription wins because idle CPU cycles during I/O waits (Python startup, file reads) are reclaimed by other pods.

**Implications for the continuum:**
- Container runtime (Docker vs native) matters <2% for CPU-bound scientific tasks.
- Scheduling strategy (1:1 vs over-subscribed) matters 4× for throughput.
- k8s admission control (wave-based scheduling) naturally handles resource contention.
- Per-task overhead is higher in k8s (pod startup, API calls), but amortised by parallelism.

### (pending) — same comparison on Ubuntu server
- **Profile**: `server`
- **Host**: Ubuntu 24 GB / 16 cores
- **Command**: `make benchmark PROFILE=server CHUNKS=20 CHUNK_MB=100 ROUNDS=2000`
- **Notes**: speedup vs Mac?

---

## Cross-SWMS comparison (to be filled as we add Pegasus, StreamFlow, …)

| Workflow            | SWMS       | Host        | Wall-clock | CPU peak | RSS peak | Notes |
|---------------------|------------|-------------|-----------:|---------:|---------:|-------|
| Mini-pipeline (5 s) | Nextflow   | Mac         |            |          |          |       |
| Mini-pipeline (5 s) | Nextflow   | Ubuntu      |            |          |          |       |
| Mini-pipeline (5 s) | Pegasus    | Ubuntu      |            |          |          |       |
| Mini-pipeline (5 s) | StreamFlow | K3s cluster |            |          |          |       |

(Pipeline equivalents in other SWMSs will be defined when the corresponding POC folders are created.)
