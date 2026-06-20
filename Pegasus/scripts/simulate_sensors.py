#!/usr/bin/env python3
import sys
import csv
import random
import math

if len(sys.argv) != 4:
    print(f"Usage: {sys.argv[0]} <device_id> <readings> <anomaly_rate>", file=sys.stderr)
    sys.exit(1)

device_id = int(sys.argv[1])
n = int(sys.argv[2])
anomaly_rate = float(sys.argv[3])

random.seed(device_id * 31337)

temp_base = 22.0 + random.uniform(-2, 2)
humidity_base = 60.0 + random.uniform(-5, 5)
pressure_base = 1013.0 + random.uniform(-3, 3)

out_file = f"device_{device_id}.csv"
with open(out_file, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["timestamp", "temperature", "humidity", "pressure"])
    for i in range(n):
        temp = temp_base + 3 * math.sin(2 * math.pi * i / 86400) + random.gauss(0, 0.5)
        humidity = humidity_base + random.gauss(0, 2.0)
        pressure = pressure_base + random.gauss(0, 0.3)

        if random.random() < anomaly_rate:
            kind = random.choice(["spike", "dropout", "drift"])
            if kind == "spike":
                temp += random.choice([-1, 1]) * random.uniform(15, 30)
            elif kind == "dropout":
                temp = float("nan")
                humidity = float("nan")
            else:
                temp += 10

        w.writerow([i, f"{temp:.2f}", f"{humidity:.2f}", f"{pressure:.2f}"])

print(f"device_{device_id}: {n} readings written to {out_file}")
