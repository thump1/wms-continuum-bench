#!/usr/bin/env python3
import sys
import csv
import math
import statistics

if len(sys.argv) != 3:
    print(f"Usage: {sys.argv[0]} <device_id> <raw.csv>", file=sys.stderr)
    sys.exit(1)

device_id = int(sys.argv[1])
raw_file = sys.argv[2]

WINDOW = 100

rows = []
with open(raw_file) as f:
    for row in csv.DictReader(f):
        try:
            t = float(row["temperature"])
            h = float(row["humidity"])
            p = float(row["pressure"])
            if math.isnan(t) or math.isnan(h) or math.isnan(p):
                continue
            rows.append({"timestamp": row["timestamp"],
                         "temperature": t, "humidity": h, "pressure": p})
        except (ValueError, KeyError):
            continue

clean, anomalies = [], []
for i, row in enumerate(rows):
    start = max(0, i - WINDOW)
    window_temps = [r["temperature"] for r in rows[start:i + 1]]
    if len(window_temps) >= 3:
        mu = statistics.mean(window_temps)
        sigma = statistics.stdev(window_temps)
        z = abs(row["temperature"] - mu) / max(sigma, 0.01)
        if z > 3.0:
            anomalies.append({**row, "z_score": f"{z:.2f}", "type": "temperature_outlier"})
            continue
    clean.append(row)

clean_file = f"device_{device_id}_clean.csv"
with open(clean_file, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["timestamp", "temperature", "humidity", "pressure"])
    w.writeheader()
    w.writerows(clean)

anomaly_file = f"device_{device_id}_anomalies.csv"
with open(anomaly_file, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["timestamp", "temperature", "humidity", "pressure", "z_score", "type"])
    w.writeheader()
    w.writerows(anomalies)

print(f"device_{device_id}: {len(clean)} clean, {len(anomalies)} anomalies")
