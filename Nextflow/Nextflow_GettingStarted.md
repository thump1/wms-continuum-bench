# Nextflow — Getting Started Guide

*Eduardo López — Phase 1 of the SWMS exploration roadmap*

This guide takes you from zero to a real bioinformatics pipeline running on your Mac in roughly two hours, most of which is the pipeline downloading test data. Mac + Docker only — no HPC, no cloud, no Kubernetes.

---

## 0. Prerequisites

You need:

- macOS with **Docker Desktop** running (you already have it)
- **Java 11+** — check with `java -version`
- About **5 GB** free disk space

If Java is missing:

```bash
brew install openjdk@17
sudo ln -sfn $(brew --prefix)/opt/openjdk@17/libexec/openjdk.jdk \
  /Library/Java/JavaVirtualMachines/openjdk-17.jdk
```

Verify Docker is running:

```bash
docker ps
```

---

## 1. Install Nextflow (5 min)

One-liner:

```bash
curl -s https://get.nextflow.io | bash
```

Move it into your PATH:

```bash
mkdir -p ~/bin
mv nextflow ~/bin/
echo 'export PATH=$HOME/bin:$PATH' >> ~/.zshrc
source ~/.zshrc
```

Verify:

```bash
nextflow -v
nextflow info
```

Expected: version 24.x or newer.

---

## 2. Hello World (5 min)

Create a file `hello.nf`:

```groovy
#!/usr/bin/env nextflow

process SAYHELLO {
    input:
    val name

    output:
    stdout

    script:
    """
    echo "Hello, ${name}, from Nextflow on Mac!"
    """
}

workflow {
    names = Channel.of('Eduardo', 'Katja', 'Salvador', 'Pedro')
    SAYHELLO(names) | view
}
```

Run it:

```bash
nextflow run hello.nf
```

You should see 4 greetings printed in any order. Note: order is non-deterministic by design — Nextflow runs tasks in parallel and only output channel order is guaranteed if you explicitly serialise it.

---

## 3. Core concepts (read once)

- **Process** — a task with declared inputs / outputs. A black box that runs a command or script.
- **Channel** — a queue of data flowing between processes. These are Nextflow's "edges" in the DAG.
- **Workflow** — composition of processes connected by channels. This is the DAG itself.
- **Executor** — *where* the process runs: `local`, `docker`, `singularity`, `slurm`, `k8s`, `awsbatch`, etc.
- **Profile** — a named bundle of configuration (e.g. `test`, `docker`, `hpc`, `server`).
- **`nextflow.config`** — config file controlling executors, resources, containers, reports.

---

## 4. Hello with Docker

Edit `hello.nf` and add `container` to the process:

```groovy
process SAYHELLO {
    container 'ubuntu:24.04'

    input:
    val name

    output:
    stdout

    script:
    """
    echo "Hello, ${name}, running inside Ubuntu container"
    """
}
```

Run it with Docker:

```bash
nextflow run hello.nf -with-docker
```

Now the process runs inside an Ubuntu container instead of directly on the Mac. This is the foundation of how Nextflow guarantees reproducibility across HPC, cloud and edge.

---

## 5. First nf-core pipeline: `nf-core/hello`

The nf-core community maintains a catalogue of validated production pipelines. There is a literal "hello" pipeline for learning:

```bash
nextflow run nf-core/hello -profile test,docker
```

What happens:

1. Nextflow downloads the pipeline from GitHub
2. Pulls the required Docker images
3. Runs a few tasks with synthetic data
4. Generates an execution report

After it finishes, look at:

- `results/` — the output files
- `.nextflow.log` — runtime log
- `work/` — intermediate task directories (each task gets a hashed folder; this is where you debug)

---

## 6. Real bioinformatics pipeline (optional, 30–60 min)

When you want to see what real scientific workflows look like, try `nf-core/rnaseq` with the test profile:

```bash
nextflow run nf-core/rnaseq -profile test,docker --outdir results/rnaseq
```

This downloads ~2 GB of test reference data and runs a complete RNA-seq pipeline on synthetic samples. Plenty of representative tasks: alignment, quantification, QC reports. Takes 30–60 min on your Mac.

---

## 7. Reading the execution report

Re-run any pipeline with reporting flags:

```bash
nextflow run hello.nf -with-report report.html -with-timeline timeline.html -with-trace
open report.html
```

You will see:

- Per-task CPU / memory / I/O metrics
- Gantt timeline of when each task ran
- Cache hits (the `-resume` optimisation)

This is the data you will eventually compare across SWMSs when you write benchmark sections for the thesis.

---

## 8. The `-resume` flag

Nextflow caches task outputs. If a run fails halfway, fix the issue and re-run with `-resume`:

```bash
nextflow run hello.nf -resume
```

It will skip already-completed tasks. This is one of Nextflow's strongest features and a topic in itself — task caching, content-addressable storage of intermediate outputs, etc.

---

## 9. Configuration: `nextflow.config`

For real work, create a `nextflow.config` next to your pipeline:

```groovy
profiles {
    standard {
        process.executor = 'local'
        process.cpus = 2
        docker.enabled = true
    }

    server {
        process.executor = 'local'
        process.cpus = 8
        process.memory = '16 GB'
        docker.enabled = true
    }

    k8s {
        process.executor = 'k8s'
        k8s.namespace = 'scientific'
        k8s.context = 'mini-continuum'
    }
}

report.enabled  = true
timeline.enabled = true
trace.enabled   = true
```

Run with a specific profile:

```bash
nextflow run hello.nf -profile server
```

You will use these profiles when you move from Mac to the Ubuntu server, and later when you spin up the K3s mini-continuum on the Windows VMs.

---

## 10. Roadmap into the thesis

Once Nextflow is comfortable on the Mac:

1. **Replicate on the Ubuntu server** — install Nextflow + Docker on Ubuntu, repeat the `nf-core/hello` run, observe resource usage on a bigger box.
2. **Move to Pegasus WMS** — install via Docker, follow the Montage tutorial. This gives you the academic-CS reference paradigm that the scheduling literature is built on.
3. **K3s cluster on the Windows VMs** — provision 3 VMs (1 control, 2 workers), install K3s, run Nextflow with `process.executor = 'k8s'`. This is your first mini-continuum.
4. **StreamFlow** — once K3s works, install StreamFlow and run the cross-environment example. This is where your thesis contributions on the IoT-edge-cloud continuum can start to take shape.

---

## Quick troubleshooting

| Symptom | Fix |
|---|---|
| `java: command not found` | `brew install openjdk@17` and re-run |
| `Cannot connect to the Docker daemon` | Start Docker Desktop |
| Pipeline downloads are slow | `nextflow pull nf-core/hello` once to cache, then re-run |
| Want to clean intermediate work | `nextflow clean -f -before <run_name>` |
| Want to clean everything | `rm -rf work/ results/ .nextflow*` |

---

## References

- Official docs — https://nextflow.io/docs/
- nf-core community — https://nf-co.re/
- nf-core pipelines catalogue — https://nf-co.re/pipelines
- Training — https://training.nextflow.io/
- Slack community — https://nf-co.re/join
