#!/usr/bin/env python3
"""
04_iot_pipeline — IoT sensor network workflow on the edge-cloud continuum.

Continuum mapping (via HTCondor ContinuumTier ClassAd):
  Edge:  SIMULATE_SENSORS → EDGE_PREPROCESS → EDGE_STATS
  Cloud: CLOUD_AGGREGATE

Equivalent to Nextflow 04_iot_pipeline.nf and StreamFlow 04_iot_pipeline.cwl.

Usage:
  python3 workflows/04_iot_pipeline.py [--devices N] [--readings N] [--placement continuum|cloud|any]
"""
import argparse
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

parser = argparse.ArgumentParser()
parser.add_argument("--devices", type=int, default=10)
parser.add_argument("--readings", type=int, default=10000)
parser.add_argument("--anomaly-rate", type=float, default=0.02)
parser.add_argument("--placement", choices=["continuum", "cloud", "edge", "any"], default="any")
args = parser.parse_args()

base_dir = Path(__file__).resolve().parent.parent
scripts_dir = base_dir / "scripts"

sc = SiteCatalog()
local = Site("local")
local.add_directories(
    Directory(Directory.SHARED_SCRATCH, str(base_dir / "work" / "iot_pipeline" / "scratch"))
    .add_file_servers(FileServer("file://" + str(base_dir / "work" / "iot_pipeline" / "scratch"), Operation.ALL)),
    Directory(Directory.LOCAL_STORAGE, str(base_dir / "results" / "iot_pipeline"))
    .add_file_servers(FileServer("file://" + str(base_dir / "results" / "iot_pipeline"), Operation.ALL)),
)
sc.add_sites(local)

condorpool = Site("condorpool")
condorpool.add_pegasus_profile(style="condor")
condorpool.add_condor_profile(universe="vanilla")
sc.add_sites(condorpool)

tc = TransformationCatalog()
simulate = Transformation("simulate_sensors.py", site="local",
                           pfn=str(scripts_dir / "simulate_sensors.py"), is_stageable=True)
preprocess = Transformation("edge_preprocess.py", site="local",
                             pfn=str(scripts_dir / "edge_preprocess.py"), is_stageable=True)
stats = Transformation("edge_stats.py", site="local",
                        pfn=str(scripts_dir / "edge_stats.py"), is_stageable=True)
aggregate = Transformation("cloud_aggregate.py", site="local",
                            pfn=str(scripts_dir / "cloud_aggregate.py"), is_stageable=True)
tc.add_transformations(simulate, preprocess, stats, aggregate)

rc = ReplicaCatalog()

wf = Workflow("iot-pipeline-wf")

stats_files = []

for dev in range(1, args.devices + 1):
    raw_csv = File(f"device_{dev}.csv")
    clean_csv = File(f"device_{dev}_clean.csv")
    anomaly_csv = File(f"device_{dev}_anomalies.csv")
    stats_json = File(f"device_{dev}_stats.json")

    sim_job = Job(simulate)
    sim_job.add_args(str(dev), str(args.readings), str(args.anomaly_rate))
    sim_job.add_outputs(raw_csv, stage_out=False, register_replica=False)

    pre_job = Job(preprocess)
    pre_job.add_args(str(dev), raw_csv)
    pre_job.add_inputs(raw_csv)
    pre_job.add_outputs(clean_csv, stage_out=False, register_replica=False)
    pre_job.add_outputs(anomaly_csv, stage_out=False, register_replica=False)

    stat_job = Job(stats)
    stat_job.add_args(str(dev), clean_csv, anomaly_csv)
    stat_job.add_inputs(clean_csv)
    stat_job.add_inputs(anomaly_csv)
    stat_job.add_outputs(stats_json, stage_out=False, register_replica=False)

    if args.placement == "continuum":
        for j in [sim_job, pre_job, stat_job]:
            j.add_profiles(Namespace.CONDOR, "requirements", '(ContinuumTier == "edge")')
    elif args.placement == "cloud":
        for j in [sim_job, pre_job, stat_job]:
            j.add_profiles(Namespace.CONDOR, "requirements", '(ContinuumTier == "cloud")')
    elif args.placement == "edge":
        for j in [sim_job, pre_job, stat_job]:
            j.add_profiles(Namespace.CONDOR, "requirements", '(ContinuumTier == "edge")')

    wf.add_jobs(sim_job, pre_job, stat_job)
    stats_files.append(stats_json)

report_json = File("iot_report.json")
agg_job = Job(aggregate)
for sf in stats_files:
    agg_job.add_inputs(sf)
    agg_job.add_args(sf)
agg_job.add_outputs(report_json, stage_out=True, register_replica=False)

if args.placement == "continuum":
    agg_job.add_profiles(Namespace.CONDOR, "requirements", '(ContinuumTier == "cloud")')
elif args.placement == "cloud":
    agg_job.add_profiles(Namespace.CONDOR, "requirements", '(ContinuumTier == "cloud")')
elif args.placement == "edge":
    agg_job.add_profiles(Namespace.CONDOR, "requirements", '(ContinuumTier == "edge")')

wf.add_jobs(agg_job)

wf.add_site_catalog(sc)
wf.add_transformation_catalog(tc)
wf.add_replica_catalog(rc)

plan_dir = base_dir / "work" / "iot_pipeline"
plan_dir.mkdir(parents=True, exist_ok=True)
os.chdir(plan_dir)

wf.plan(
    dir=str(plan_dir),
    sites=["condorpool"],
    staging_sites={"condorpool": "local"},
    output_sites=["local"],
    submit=True,
)
