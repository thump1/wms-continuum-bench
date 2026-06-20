#!/usr/bin/env python3
"""
00_hello — Minimal Pegasus workflow: greet 4 people via HTCondor.

Equivalent to Nextflow 00_hello.nf and StreamFlow 00_hello.cwl.
"""
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

NAMES = ["Eduardo", "Katja", "Salvador", "Pedro"]
SCRIPT = "say_hello.py"

base_dir = Path(__file__).resolve().parent.parent
scripts_dir = base_dir / "scripts"

sc = SiteCatalog()

local = Site("local")
local.add_directories(
    Directory(Directory.SHARED_SCRATCH, str(base_dir / "work" / "hello" / "scratch"))
    .add_file_servers(FileServer("file://" + str(base_dir / "work" / "hello" / "scratch"), Operation.ALL)),
    Directory(Directory.LOCAL_STORAGE, str(base_dir / "results" / "hello"))
    .add_file_servers(FileServer("file://" + str(base_dir / "results" / "hello"), Operation.ALL)),
)
sc.add_sites(local)

condorpool = Site("condorpool")
condorpool.add_pegasus_profile(style="condor")
condorpool.add_condor_profile(universe="vanilla")
sc.add_sites(condorpool)

tc = TransformationCatalog()
say_hello = Transformation(
    SCRIPT,
    site="local",
    pfn=str(scripts_dir / SCRIPT),
    is_stageable=True,
)
tc.add_transformations(say_hello)

rc = ReplicaCatalog()

wf = Workflow("hello-wf")

for name in NAMES:
    out = File(f"hello_{name}.txt")
    job = Job(say_hello)
    job.add_args(name)
    job.set_stdout(out, stage_out=True, register_replica=False)
    wf.add_jobs(job)

wf.add_site_catalog(sc)
wf.add_transformation_catalog(tc)
wf.add_replica_catalog(rc)

plan_dir = base_dir / "work" / "hello"
plan_dir.mkdir(parents=True, exist_ok=True)
os.chdir(plan_dir)

wf.plan(
    dir=str(plan_dir),
    sites=["condorpool"],
    staging_sites={"condorpool": "local"},
    output_sites=["local"],
    submit=True,
)
