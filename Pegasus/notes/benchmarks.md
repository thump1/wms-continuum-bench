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

**Hardware asymmetry**: Edge has 2 vCPU vs Cloud's 4 vCPU, modelling real continuum resource constraints.

## Run log

### Template

```
Date:        YYYY-MM-DD HH:MM
Workflow:    workflows/XX_name.py
Placement:   any / continuum / cloud
Host:        3-node HTCondor cluster (VMware VMs)
Command:     make <target>
Wall-clock:  m:ss
Notes:       observations, errors, surprises
```

---

## Runs

(Benchmarks will be recorded here as pipelines are executed.)

---

## Observations

(To be filled during benchmarking.)
