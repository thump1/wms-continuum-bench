# SWMS POC — Nextflow

Proof of concept for Nextflow as part of the doctoral thesis exploration of Scientific Workflow Management Systems on the IoT-Edge-Cloud Continuum.

## Layout

```
Nextflow/
├── README.md                    This file
├── Nextflow_GettingStarted.md   Step-by-step install + first-run guide
├── nextflow.config              Global config with profiles (Mac / server / K3s)
├── Makefile                     Shortcuts: make hello / make minipipeline / make clean
├── .gitignore
├── pipelines/                   DAGs (.nf files), in order of complexity
│   ├── 00_hello.nf              Bare hello world (no container)
│   ├── 01_hello_docker.nf       Hello world with Ubuntu container
│   ├── 02_minipipeline.nf       Multi-stage DAG: generate → analyse → summarise
│   ├── 03_benchmark.nf         Configurable benchmark: ingest → preprocess → analyze → aggregate
│   └── 04_iot_pipeline.nf     IoT continuum workflow: sensors → edge preprocessing → cloud analytics
├── data/                        Test inputs
│   └── samples.csv
├── reports/                     Auto-generated HTML reports (one per run)
├── results/                     Pipeline outputs (publishDir target)
└── notes/                       Free-form observations
    └── benchmarks.md
```

## How to run (Mac with Docker)

Requires Nextflow installed on the host (see `Nextflow_GettingStarted.md`):

```bash
make info             # show Nextflow version and current profile
make hello            # run 00_hello.nf (no container)
make hello-docker     # run 01_hello_docker.nf (Ubuntu container)
make minipipeline     # run 02_minipipeline.nf (multi-stage DAG)
make benchmark        # run 03_benchmark.nf (performance test, defaults: 10×25 MB, 500 rounds)
make iot              # run 04_iot_pipeline.nf (IoT continuum workflow, defaults: 10 devices, 10K readings)
```

Scale up for heavier runs:

```bash
make benchmark CHUNKS=20 CHUNK_MB=100 ROUNDS=1000
make iot DEVICES=50 READINGS=100000
```

## Profiles

Defined in `nextflow.config`. Pass with `-profile <name>`.

| Profile  | Where               | Executor | Resources           |
|----------|---------------------|----------|---------------------|
| standard | Mac local           | local    | 2 cores, 4 GB       |
| docker   | Mac local + Docker  | local    | 2 cores, 4 GB       |
| server   | Ubuntu server       | local    | 8 cores, 16 GB      |
| k8s      | K3s mini-continuum  | k8s      | 2 cores, 2 GB       |

## Reports

Every run automatically produces, under `reports/`:

- `report-<timestamp>.html` — per-task CPU, memory, IO metrics
- `timeline-<timestamp>.html` — Gantt chart of task execution
- `trace-<timestamp>.txt` — machine-readable trace (used later for the thesis benchmarks table)

## Cleanup

```bash
make clean        # remove work/ (intermediate task dirs) only
make clean-all    # remove work/, results/, reports/, .nextflow*
```

## Next steps in the SWMS roadmap

1. Run all three pipelines on Mac with `docker` profile
2. Replicate on Ubuntu server with `server` profile, compare reports
3. Set up K3s cluster on Windows VMs, run with `k8s` profile
4. Move on to `../Pegasus/` POC (next folder)
