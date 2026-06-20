#!/usr/bin/env python3
import sys
import json
import statistics

if len(sys.argv) < 2:
    report = {
        "num_devices": 0,
        "total_readings_clean": 0,
        "total_anomalies": 0,
        "anomaly_rate_pct": 0,
        "error": "no stats files provided",
        "per_device": [],
    }
    with open("iot_report.json", "w") as f:
        json.dump(report, f, indent=2)
    print("WARNING: no stats files provided, wrote empty report", file=sys.stderr)
    sys.exit(0)

devices = []
for path in sys.argv[1:]:
    with open(path) as fh:
        devices.append(json.load(fh))

devices.sort(key=lambda d: d["device_id"])

temp_means = [d["temperature"]["mean"] for d in devices]
humid_means = [d["humidity"]["mean"] for d in devices]
press_means = [d["pressure"]["mean"] for d in devices]
total_anomalies = sum(d["anomalies_detected"] for d in devices)
total_readings = sum(d["readings_clean"] for d in devices)
total_all = total_readings + total_anomalies

report = {
    "num_devices": len(devices),
    "total_readings_clean": total_readings,
    "total_anomalies": total_anomalies,
    "anomaly_rate_pct": round(total_anomalies / total_all * 100, 2) if total_all else 0,
    "system_temperature": {
        "mean": round(statistics.mean(temp_means), 2),
        "stdev_across_devices": round(statistics.stdev(temp_means), 2) if len(temp_means) > 1 else 0,
    },
    "system_humidity": {
        "mean": round(statistics.mean(humid_means), 2),
        "stdev_across_devices": round(statistics.stdev(humid_means), 2) if len(humid_means) > 1 else 0,
    },
    "system_pressure": {
        "mean": round(statistics.mean(press_means), 2),
        "stdev_across_devices": round(statistics.stdev(press_means), 2) if len(press_means) > 1 else 0,
    },
    "per_device": devices,
}

with open("iot_report.json", "w") as f:
    json.dump(report, f, indent=2)

print(f"IoT Sensor Network — Analytics Report")
print(f"{'=' * 55}")
print(f"Devices:          {len(devices)}")
print(f"Readings (clean): {total_readings:,}")
print(f"Anomalies:        {total_anomalies:,}  ({report['anomaly_rate_pct']}%)")
print(f"Temp mean:        {report['system_temperature']['mean']:.1f} C")
print(f"Humidity mean:    {report['system_humidity']['mean']:.1f} %")
print(f"Pressure mean:    {report['system_pressure']['mean']:.1f} hPa")
