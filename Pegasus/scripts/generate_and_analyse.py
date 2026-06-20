#!/usr/bin/env python3
import sys
import os
import hashlib
import json

if len(sys.argv) != 3:
    print(f"Usage: {sys.argv[0]} <sample_id> <size>", file=sys.stderr)
    sys.exit(1)

sample_id = sys.argv[1]
size = int(sys.argv[2])

data = os.urandom(size)

dat_file = f"{sample_id}.dat"
with open(dat_file, "wb") as f:
    f.write(data)

sha = hashlib.sha256(data).hexdigest()

stats = {
    "sample_id": sample_id,
    "length": size,
    "sha256": sha,
}

stats_file = f"{sample_id}_stats.json"
with open(stats_file, "w") as f:
    json.dump(stats, f, indent=2)

print(f"{sample_id}: {size} bytes, sha256={sha[:16]}...")
