#!/usr/bin/env python3
"""
02_minipipeline — Fan-out / fan-in DAG via Pegasus + HTCondor.

5 generate_and_analyse jobs (scatter) → 1 summarise job (gather).
Equivalent to Nextflow 02_minipipeline.nf and StreamFlow 02_minipipeline.cwl.
"""
import csv
import sys
import os
from pathlib import Path

from Pegasus.api import (
    Workflow,
    Job,
    File,
    Transformation,
    TransformationCatalog,
    SiteCatalog,
    Site,
    Directory,
    FileServer,
    Operation,
    ReplicaCatalog,
    Namespace,
)

base_dir = Path(__file__).resolve().parent.parent
scripts_dir = base_dir / "scripts"
data_dir = base_dir / "data"

SAMPLES_CSV = data_dir / "samples.csv"

sc = SiteCatalog()
local = Site("local")
local.add_directories(
    Directory(Directory.SHARED_SCRATCH, str(base_dir / "work" / "minipipeline" / "scratch"))
    .add_file_servers(FileServer("file://" + str(base_dir / "work" / "minipipeline" / "scratch"), Operation.ALL)),
    Directory(Directory.LOCAL_STORAGE, str(base_dir / "results" / "minipipeline"))
    .add_file_servers(FileServer("file://" + str(base_dir / "results" / "minipipeline"), Operation.ALL)),
)
sc.add_sites(local)

condorpool = Site("condorpool")
condorpool.add_pegasus_profile(style="condor")
condorpool.add_condor_profile(universe="vanilla")
sc.add_sites(condorpool)

tc = TransformationCatalog()
gen_analyse = Transformation(
    "generate_and_analyse.py",
    site="local",
    pfn=str(scripts_dir / "generate_and_analyse.py"),
    is_stageable=True,
)
summarise = Transformation(
    "summarise.py",
    site="local",
    pfn=str(scripts_dir / "summarise.py"),
    is_stageable=True,
)
tc.add_transformations(gen_analyse, summarise)

rc = ReplicaCatalog()

wf = Workflow("minipipeline-wf")

samples = []
with open(SAMPLES_CSV) as f:
    for row in csv.DictReader(f):
        samples.append((row["sample_id"], int(row["size"])))

stats_files = []
for sample_id, size in samples:
    stats_out = File(f"{sample_id}_stats.json")

    job = Job(gen_analyse)
    job.add_args(sample_id, str(size))
    job.add_outputs(stats_out, stage_out=False, register_replica=False)
    wf.add_jobs(job)

    stats_files.append(stats_out)

summary_out = File("summary.json")
sum_job = Job(summarise)
for sf in stats_files:
    sum_job.add_inputs(sf)
    sum_job.add_args(sf)
sum_job.add_outputs(summary_out, stage_out=True, register_replica=False)
wf.add_jobs(sum_job)

wf.add_site_catalog(sc)
wf.add_transformation_catalog(tc)
wf.add_replica_catalog(rc)

plan_dir = base_dir / "work" / "minipipeline"
plan_dir.mkdir(parents=True, exist_ok=True)
os.chdir(plan_dir)

wf.plan(
    dir=str(plan_dir),
    sites=["condorpool"],
    staging_sites={"condorpool": "local"},
    output_sites=["local"],
    submit=True,
)
