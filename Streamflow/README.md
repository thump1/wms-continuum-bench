# StreamFlow POC

Proof-of-concept evaluation of [StreamFlow](https://github.com/alpha-unito/streamflow) (Aldinucci et al., Univ. of Torino) as a Scientific Workflow Management System for the IoT-edge-cloud continuum.

StreamFlow uses [CWL](https://www.commonwl.org/) (Common Workflow Language) for workflow definition and separates execution deployment into its own YAML configuration. This decoupling is its key differentiator: the same CWL workflow can run locally, in Docker, on an SSH-reachable server, or across a hybrid continuum — by swapping the StreamFlow YAML file.

## Prerequisites

- Python 3.12 (StreamFlow 0.1.6 does not support Python 3.13+)
- Docker Desktop (for containerised deployments)
- SSH access to the Ubuntu server (for SSH/hybrid deployments)

## Setup

```bash
make setup          # creates .venv, installs streamflow + cwltool
source .venv/bin/activate
streamflow version  # should print StreamFlow version 0.1.6
```

Or manually:

```bash
python3.12 -m venv .venv
.venv/bin/pip install streamflow
```

## Pipelines (ported from Nextflow)

| Pipeline | CWL workflow | Nextflow equivalent | Description |
|----------|-------------|---------------------|-------------|
| `00_hello` | `workflows/00_hello.cwl` | `pipelines/00_hello.nf` | Bare hello world, no containers |
| `01_hello_docker` | `workflows/01_hello_docker.cwl` | `pipelines/01_hello_docker.nf` | Hello world inside Ubuntu container |
| `02_minipipeline` | `workflows/02_minipipeline.cwl` | `pipelines/02_minipipeline.nf` | Fan-out / fan-in multi-stage DAG |
| `04_iot_pipeline` | `workflows/04_iot_pipeline.cwl` | `pipelines/04_iot_pipeline.nf` | IoT continuum (simulate → edge → cloud) |

## Deployment configurations

| File | Models | Use case |
|------|--------|----------|
| `streamflow-hello.yml` | local | Run 00_hello natively on the host |
| `streamflow-hello-docker.yml` | Docker (ubuntu:24.04) | Run 01_hello_docker in container |
| `streamflow-minipipeline.yml` | Docker (python:3.12) | Run 02_minipipeline in containers |
| `streamflow-iot.yml` | Docker (python:3.12) | Run 04_iot locally in Docker |
| `streamflow-iot-ssh.yml` | SSH (Ubuntu server) | Run 04_iot on remote server |
| `streamflow-iot-hybrid.yml` | Docker + SSH | IoT/Cloud local, Edge on server |
| `streamflow-iot-k8s.yml` | Helm3 (k3d) | Run 04_iot on k8s, all on cloud worker |
| `streamflow-iot-k8s-continuum.yml` | Helm3 (k3d) | 04_iot: edge steps on edge node, cloud on cloud |
| `streamflow-iot-k8s-cloud-only.yml` | Helm3 (k3d) | 04_iot: cloud node only, no edge pod |
| `streamflow-iot-k8s-latency.yml` | Helm3 (k3d) | 05_iot_latency: edge+cloud with simulated WAN delay |

## Running

```bash
make hello              # local, no Docker
make hello-docker       # Docker ubuntu:24.04
make minipipeline       # Docker python:3.12
make iot                # Docker python:3.12
```

For SSH deployments, edit the `<UBUNTU_SERVER_HOST>` and `<UBUNTU_SERVER_USER>` placeholders in the corresponding YAML:

```bash
make iot-ssh            # all steps on Ubuntu server
make iot-hybrid         # IoT+Cloud local, Edge on server
```

## Kubernetes (k3d) deployments

Requires the k3d `continuum` cluster (see `SWMS-POC/k3d/`). StreamFlow uses the Helm3 connector to deploy persistent worker pods on labeled nodes, then executes CWL jobs via the k8s API.

```bash
# Start k3d cluster (if not running)
cd ../k3d && make up && cd ../StreamFlow

# Placement experiments
make iot-k8s              # all steps on cloud worker
make iot-k8s-continuum    # edge steps on edge node, cloud on cloud node
make iot-k8s-cloud-only   # cloud node only (no edge pod)

# Latency experiments (simulated WAN delay between edge↔cloud)
make iot-k8s-latency LATENCY=0     # baseline
make iot-k8s-latency LATENCY=200   # 200ms regional WAN
make iot-k8s-latency LATENCY=500   # 500ms intercontinental
```

The Helm chart at `helm/streamflow-worker/` deploys two pods: `cloud-worker` (on `continuum-tier=cloud` node) and `edge-worker` (on `continuum-tier=edge` node). The CWL workflows are identical across all configurations — only the StreamFlow YAML bindings change.

## Validation

```bash
make validate           # validates all CWL files with cwltool
```

## Directory structure

```
StreamFlow/
├── Makefile
├── streamflow-*.yml         ← deployment configs (one per target)
├── workflows/               ← CWL Workflow definitions
│   ├── 00_hello.cwl
│   ├── 01_hello_docker.cwl
│   ├── 02_minipipeline.cwl
│   └── 04_iot_pipeline.cwl
├── tools/                   ← CWL CommandLineTool definitions
│   ├── say_hello.cwl
│   ├── say_hello_info.cwl
│   ├── generate_and_analyse.cwl
│   ├── summarise.cwl
│   ├── device_pipeline.cwl
│   ├── device_pipeline_latency.cwl  ← latency-aware variant (simulated WAN delay)
│   └── cloud_aggregate.cwl
├── helm/streamflow-worker/  ← Helm chart for k3d worker pods
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/           ← cloud-deployment.yaml, edge-deployment.yaml
├── inputs/                  ← CWL input files for latency experiments
│   ├── latency-0ms.yml
│   ├── latency-50ms.yml
│   ├── latency-200ms.yml
│   └── latency-500ms.yml
├── data/samples.csv         ← same samples as Nextflow POC
├── notes/benchmarks.md      ← run log + cross-SWMS comparison
├── reports/                 ← auto-generated reports
└── results/                 ← pipeline outputs
```

## Known issues (StreamFlow 0.1.6 on macOS)

Two bugs in StreamFlow 0.1.6 require runtime patches (applied in `.venv/` after `make setup`):

1. **Docker container ID pollution**: Docker Desktop writes a `--disable-content-trust` deprecation warning to stdout. StreamFlow captures stdout for the container ID, so `docker exec` commands fail silently. Patch: `container.py` — take only the last line of `docker run` stdout.

2. **macOS `/tmp` symlink**: macOS resolves `/tmp` to `/private/tmp`. StreamFlow's glob path validation compares resolved paths against unresolved job directories and rejects them. Patch: `token_processor.py` — compare against `os.path.realpath()` of both directories.

Additionally, **chained scatter** (scatter → gather → scatter) is broken in StreamFlow 0.1.6 — the second scatter's input tokens are dropped. The CWL is valid (runs correctly with cwltool). Workaround: merge per-item stages into a single tool so only one scatter level is needed.

Run `make setup-patches` after `make setup` to apply both patches automatically.

## Key differences from Nextflow

| Aspect | Nextflow | StreamFlow |
|--------|----------|------------|
| Workflow language | Nextflow DSL (Groovy-based) | CWL (YAML/JSON standard) |
| Container config | `container` directive in .nf | Separate streamflow YAML bindings |
| Multi-site | Custom executor plugins | Native cross-environment via YAML |
| Scatter/gather | Channel operators (`splitCsv`, `collect`) | CWL `ScatterFeatureRequirement` |
| Parameterisation | `params.*` in `nextflow.config` | CWL inputs with defaults |
