# Pegasus WMS POC

Proof-of-concept evaluation of [Pegasus WMS](https://pegasus.isi.edu/) (Deelman et al., USC ISI) as a Scientific Workflow Management System for the IoT-edge-cloud continuum.

Pegasus uses a Python API for workflow definition and relies on HTCondor for job scheduling and execution. Jobs are dispatched across a 3-node HTCondor cluster with custom `ContinuumTier` ClassAds for edge/cloud placement.

## Infrastructure

| Node | Hostname | Role | vCPU | RAM |
|------|----------|------|------|-----|
| CM/Submit | pegasus-cm | Central Manager + Schedd | 2 | 3.3 GB |
| Cloud | pegasus-cloud | Execute node (cloud tier) | 4 | 15 GB |
| Edge | pegasus-edge | Execute node (edge tier) | 2 | 7.2 GB |

All Ubuntu 26.04 LTS on VMware Workstation Pro (Ryzen 7-3700X host, 64 GB).

## Prerequisites

- HTCondor 25.x cluster (3 nodes, IDTOKENS auth)
- Pegasus WMS 5.x (on CM node)
- Python 3.14 (on all nodes)

## Setup

See `setup/` for installation scripts:

```bash
# On all 3 nodes:
bash setup/install-htcondor.sh
bash setup/configure-cluster.sh <cm|cloud|edge>

# On CM only:
bash setup/install-pegasus.sh
```

## Pipelines (ported from Nextflow/StreamFlow)

| Pipeline | Workflow | Nextflow equiv. | Description |
|----------|----------|-----------------|-------------|
| `00_hello` | `workflows/00_hello.py` | `00_hello.nf` | 4 greeting jobs |
| `02_minipipeline` | `workflows/02_minipipeline.py` | `02_minipipeline.nf` | Fan-out/fan-in DAG |
| `04_iot_pipeline` | `workflows/04_iot_pipeline.py` | `04_iot_pipeline.nf` | IoT continuum (10 devices, edge/cloud placement) |

## Running (on CM node)

```bash
make hello              # 4 jobs, any node
make minipipeline       # 5+1 fan-out/fan-in, any node
make iot                # 10 devices, any node
make iot-continuum      # 10 devices, edge/cloud placement
make iot-cloud          # 10 devices, cloud-only
make status             # cluster + workflow status
make validate-output    # diff Pegasus vs Nextflow output
```

## Continuum placement

Jobs target specific nodes via HTCondor ClassAd requirements:

```python
job.add_profiles(Namespace.CONDOR, "requirements", '(ContinuumTier == "edge")')
```

## Data staging

Uses `condorio` — HTCondor routes all file transfers through the submit node. No shared filesystem (NFS) required.

## Directory structure

```
Pegasus/
├── Makefile
├── README.md
├── scripts/                 ← standalone Python scripts
│   ├── say_hello.py
│   ├── generate_and_analyse.py
│   ├── summarise.py
│   ├── simulate_sensors.py
│   ├── edge_preprocess.py
│   ├── edge_stats.py
│   └── cloud_aggregate.py
├── workflows/               ← Pegasus workflow definitions (Python API)
│   ├── 00_hello.py
│   ├── 02_minipipeline.py
│   └── 04_iot_pipeline.py
├── data/samples.csv
├── notes/benchmarks.md
├── results/
└── setup/
    ├── install-htcondor.sh
    ├── install-pegasus.sh
    └── configure-cluster.sh
```

## Key differences from Nextflow and StreamFlow

| Aspect | Nextflow | StreamFlow | Pegasus |
|--------|----------|------------|---------|
| Workflow language | Nextflow DSL (Groovy) | CWL (YAML) | Python API |
| Scheduler | Built-in | Built-in | HTCondor (external) |
| Container model | Per-task container | Persistent container | No containers (bare-metal) |
| Multi-site | Custom executor plugins | YAML bindings | HTCondor ClassAd matching |
| Data staging | Work dir / publishDir | StreamFlow runtime | condorio (HTCondor file transfer) |
| DAG shape (IoT 10x) | 31 jobs (4-stage modular) | 12 jobs (merged edge stages) | 31 jobs (4-stage modular) |
