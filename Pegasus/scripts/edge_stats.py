#!/usr/bin/env python3
import sys
import csv
import json
import statistics

if len(sys.argv) != 4:
    print(f"Usage: {sys.argv[0]} <device_id> <clean.csv> <anomalies.csv>", file=sys.stderr)
    sys.exit(1)

device_id = int(sys.argv[1])
clean_file = sys.argv[2]
anomaly_file = sys.argv[3]

temps, humids, pressures = [], [], []
with open(clean_file) as f:
    for row in csv.DictReader(f):
        temps.append(float(row["temperature"]))
        humids.append(float(row["humidity"]))
        pressures.append(float(row["pressure"]))

anomaly_count = 0
with open(anomaly_file) as f:
    anomaly_count = sum(1 for _ in csv.DictReader(f))


def summarise(values):
    return {"min": round(min(values), 2),
            "max": round(max(values), 2),
            "mean": round(statistics.mean(values), 2),
            "stdev": round(statistics.stdev(values), 2) if len(values) > 1 else 0,
            "count": len(values)}


result = {"device_id": device_id,
          "readings_clean": len(temps),
          "anomalies_detected": anomaly_count,
          "temperature": summarise(temps),
          "humidity": summarise(humids),
          "pressure": summarise(pressures)}

stats_file = f"device_{device_id}_stats.json"
with open(stats_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"device_{device_id}: {len(temps)} clean readings, {anomaly_count} anomalies")
