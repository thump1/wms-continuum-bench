# wms-continuum-bench

Benchmark and evaluation of Scientific Workflow Management Systems (SWMSs) on the IoT-edge-cloud continuum. Part of Eduardo Lopez's doctoral thesis at Universidad Miguel Hernandez de Elche.

Three SWMSs are evaluated using the **same IoT sensor workload** (simulate sensors, edge preprocessing with z-score anomaly detection, edge statistics, cloud aggregation) across different deployment targets, placement strategies, and network conditions.

## Evaluated systems

| SWMS | Version | Language | Scheduler | Deployment targets |
|------|---------|----------|-----------|-------------------|
| [Nextflow](https://www.nextflow.io/) | 24.x | Nextflow DSL (Groovy) | Built-in | Local, Docker, k8s (k3d) |
| [StreamFlow](https://github.com/alpha-unito/streamflow) | 0.1.6 | CWL (YAML) | Built-in | Local, Docker, SSH, k8s (k3d Helm3) |
| [Pegasus](https://pegasus.isi.edu/) | 5.1.2 | Python API | HTCondor 25.x | 3-node VM cluster (VMware) |

## Repository structure

```
wms-continuum-bench/
├── README.md                      ← this file
├── cross-SWMS-benchmarks.md       ← consolidated results across all 3 SWMSs
│
├── Nextflow/                      ← Nextflow POC (Mac local + Docker + k8s)
│   ├── pipelines/                    00_hello, 01_hello_docker, 02_minipipeline,
│   │                                 03_benchmark, 04_iot_pipeline (.nf)
│   ├── nextflow.config               profiles: standard, docker, server, k8s
│   ├── Makefile                       make hello / iot / benchmark / clean
│   └── notes/benchmarks.md
│
├── Streamflow/                    ← StreamFlow POC (Docker + SSH + k8s)
│   ├── workflows/                    00_hello, 01_hello_docker, 02_minipipeline,
│   │                                 04_iot_pipeline, 05_iot_pipeline_latency (.cwl)
│   ├── tools/                        CWL CommandLineTool definitions
│   ├── streamflow-*.yml              deployment configs (10 variants)
│   ├── scripts/                      tc netem latency injection for k3d
│   ├── dashboard/app.py              Streamlit provenance dashboard
│   ├── Makefile                       make iot / iot-k8s-continuum / tc-inject / ...
│   └── notes/benchmarks.md
│
├── Pegasus/                       ← Pegasus POC (3-node HTCondor cluster)
│   ├── workflows/                    00_hello, 02_minipipeline, 04_iot_pipeline (.py)
│   ├── scripts/                      standalone Python scripts + experiment automation
│   ├── setup/                        HTCondor + Pegasus install scripts
│   ├── Makefile                       make iot / iot-edge / iot-cloud / job-timing / ...
│   └── notes/benchmarks.md
│
└── k3d/                           ← k3d cluster config for k8s deployments
    ├── cluster.yaml                  3-node: 1 server + cloud agent + edge agent
    ├── manifests/                    namespace, RBAC, PVC for Nextflow/StreamFlow
    └── Makefile                      make up / down / status
```

## IoT continuum pipeline

The main benchmark pipeline models an IoT sensor network with edge preprocessing and cloud analytics. All three SWMSs implement the same algorithm with identical output.

```
┌──────────────┐   ┌─────────────────┐   ┌────────────┐   ┌──────────────────┐
│  SIMULATE    │──▶│ EDGE_PREPROCESS  │──▶│ EDGE_STATS │──▶│ CLOUD_AGGREGATE  │
│  SENSORS     │   │ (z-score anomaly │   │ (per-device│   │ (cross-device    │
│  (per device)│   │  detection)      │   │  summary)  │   │  report)         │
└──────────────┘   └─────────────────┘   └────────────┘   └──────────────────┘
     x10 devices (parallel scatter)         ──────▶          x1 (gather)
```

Default: 10 devices, 10,000 readings each. Output: `iot_report.json` with 98,015 clean readings, 1,326 anomalies (1.33%), matching across all three SWMSs.

## Experiments run

### Placement strategies
How does constraining jobs to specific nodes affect performance?

| SWMS | Placement | Wall-clock | Environment |
|------|-----------|-----------|-------------|
| Nextflow | Docker (parallel) | ~1s compute | Mac (local) |
| StreamFlow | k8s cloud-only | 23.6s | k3d (local) |
| StreamFlow | k8s continuum | 24.2s | k3d (local) |
| Pegasus | cloud-only (4 vCPU) | 2m 31s | HTCondor VMs |
| Pegasus | edge-only (2 vCPU) | 2m 37s | HTCondor VMs |
| Pegasus | continuum | 2m 51s | HTCondor VMs |

### Latency injection (tc netem)
How does real network latency affect workflow execution?

| SWMS | 0ms | 50ms | 200ms | 500ms |
|------|-----|------|-------|-------|
| StreamFlow (k8s) | 2m 38s | 1m 43s* | 2m 53s | FAILED |
| Pegasus (HTCondor) | 2m 56s | 3m 42s (+26%) | 5m 12s (+77%) | — |

*StreamFlow 50ms required retry (WebSocket error)

### Scale test (10 devices x 100K readings)

| SWMS | Edge-only | Cloud-only | Dominant factor |
|------|-----------|-----------|-----------------|
| Nextflow | — | — | Not tested on HTCondor |
| Pegasus | 3m 46s | 3m 11s | Compute (cloud 4 slots wins) |

## Key findings

1. **Condorio bottleneck inverts expectations.** At small workloads (10K), the 2-vCPU edge node outperforms the 4-vCPU cloud node because fewer concurrent transfer slots reduce contention on the submit host.

2. **Control plane amplification is universal.** Both StreamFlow (WebSocket k8s exec) and Pegasus (CEDAR/condorio) amplify network latency 11-15x beyond naive predictions. Neither separates management from data traffic.

3. **Compute/transfer crossover.** Between 10K and 100K readings, the bottleneck shifts from transfer overhead (edge wins) to compute parallelism (cloud wins).

4. **Protocol resilience varies.** StreamFlow's WebSocket-based k8s exec fails at 500ms. Pegasus's CEDAR protocol degrades gracefully but still shows significant amplification.

5. **SDN/NFV network slicing is justified.** 50ms regional WAN latency causes +26% wall-time degradation. Protecting management traffic would reduce this to near-zero.

## Hardware

| Resource | Specification | Used by |
|----------|--------------|---------|
| Mac M3 Pro | 11 cores, 18 GB | Nextflow, StreamFlow, k3d |
| VMware cluster (Win host) | Ryzen 7-3700X, 64 GB | Pegasus HTCondor (3 VMs) |
| Ubuntu server | 24 GB RAM | StreamFlow SSH target |

## How to browse

- **Start here**: [`cross-SWMS-benchmarks.md`](cross-SWMS-benchmarks.md) for the consolidated comparison across all three SWMSs, including latency experiments and architectural analysis.
- **Per-SWMS details**: each `<SWMS>/notes/benchmarks.md` has the raw run log and observations.
- **Per-SWMS setup**: each `<SWMS>/README.md` explains how to install, configure, and run.
- **Pipeline code**: `Nextflow/pipelines/`, `Streamflow/workflows/` + `tools/`, `Pegasus/workflows/` + `scripts/`.

## Thesis context

This repository supports **Objective O1** (state of the art) and feeds into **O2** (resource requirements analysis) and **O3** (proactive resource management) of the doctoral thesis *Heterogeneous Scientific Workflows on the IoT-Edge-Cloud Continuum* (UMH, 2025-2029).

Supervisors: Dr. Katja Gilly, Dr. Salvador Alcaraz, Dr. Pedro Juan Roig.
