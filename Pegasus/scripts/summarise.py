#!/usr/bin/env python3
import sys
import json
import glob
from datetime import datetime, timezone

if len(sys.argv) < 2:
    print(f"Usage: {sys.argv[0]} <stats1.json> [stats2.json ...]", file=sys.stderr)
    sys.exit(1)

stats_files = sys.argv[1:]
samples = []
for path in stats_files:
    with open(path) as f:
        samples.append(json.load(f))

summary = {
    "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "num_samples": len(samples),
    "total_bytes": sum(s["length"] for s in samples),
    "samples": samples,
}

with open("summary.json", "w") as f:
    json.dump(summary, f, indent=2)

print(f"Mini-pipeline summary")
print(f"Generated:  {summary['generated']}")
print(f"Samples:    {summary['num_samples']}")
print(f"Total bytes: {summary['total_bytes']:,}")
print("----")
for s in samples:
    print(f"  {s['sample_id']}: {s['length']} bytes, sha256={s['sha256'][:16]}...")
