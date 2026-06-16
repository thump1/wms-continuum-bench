#!/usr/bin/env nextflow

/*
 * 04_iot_pipeline.nf — IoT sensor network workflow on the edge-cloud continuum.
 *
 * Continuum mapping:
 *   IoT layer:   SIMULATE_SENSORS  (data acquisition from device fleet)
 *   Edge layer:  EDGE_PREPROCESS   (local filtering + anomaly detection)
 *                EDGE_STATS        (per-device aggregation)
 *   Cloud layer: CLOUD_AGGREGATE   (cross-device analytics + dashboard)
 *
 * Run:
 *   nextflow run pipelines/04_iot_pipeline.nf -profile docker
 *   nextflow run pipelines/04_iot_pipeline.nf -profile docker --num_devices 50 --readings_per_device 100000
 */

params.num_devices         = 10
params.readings_per_device = 10000
params.anomaly_rate        = 0.02
params.outdir              = "${projectDir}/../results/iot_pipeline"

// ---------------------------------------------------------------------------
//  IoT layer — sensor data acquisition
// ---------------------------------------------------------------------------

process SIMULATE_SENSORS {
    tag "device_${device_id}"
    container 'python:3.12'

    input:
    val device_id

    output:
    tuple val(device_id), path("device_${device_id}.csv")

    script:
    """
    python3 << 'PYEOF'
import csv, random, math

device_id = ${device_id}
n = ${params.readings_per_device}
anomaly_rate = ${params.anomaly_rate}

random.seed(device_id * 31337)

temp_base = 22.0 + random.uniform(-2, 2)
humidity_base = 60.0 + random.uniform(-5, 5)
pressure_base = 1013.0 + random.uniform(-3, 3)

with open(f'device_{device_id}.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['timestamp', 'temperature', 'humidity', 'pressure'])
    for i in range(n):
        temp = temp_base + 3 * math.sin(2 * math.pi * i / 86400) + random.gauss(0, 0.5)
        humidity = humidity_base + random.gauss(0, 2.0)
        pressure = pressure_base + random.gauss(0, 0.3)

        if random.random() < anomaly_rate:
            kind = random.choice(['spike', 'dropout', 'drift'])
            if kind == 'spike':
                temp += random.choice([-1, 1]) * random.uniform(15, 30)
            elif kind == 'dropout':
                temp = float('nan')
                humidity = float('nan')
            else:
                temp += 10

        w.writerow([i, f'{temp:.2f}', f'{humidity:.2f}', f'{pressure:.2f}'])
PYEOF
    """
}

// ---------------------------------------------------------------------------
//  Edge layer — local preprocessing and anomaly detection
// ---------------------------------------------------------------------------

process EDGE_PREPROCESS {
    tag "device_${device_id}"
    container 'python:3.12'

    input:
    tuple val(device_id), path(raw_data)

    output:
    tuple val(device_id), path("device_${device_id}_clean.csv"), path("device_${device_id}_anomalies.csv")

    script:
    """
    python3 << 'PYEOF'
import csv, math, statistics

device_id = ${device_id}
WINDOW = 100

rows = []
with open('${raw_data}') as f:
    for row in csv.DictReader(f):
        try:
            t = float(row['temperature'])
            h = float(row['humidity'])
            p = float(row['pressure'])
            if math.isnan(t) or math.isnan(h) or math.isnan(p):
                continue
            rows.append({'timestamp': row['timestamp'],
                         'temperature': t, 'humidity': h, 'pressure': p})
        except (ValueError, KeyError):
            continue

clean, anomalies = [], []
for i, row in enumerate(rows):
    start = max(0, i - WINDOW)
    window_temps = [r['temperature'] for r in rows[start:i + 1]]
    if len(window_temps) >= 3:
        mu = statistics.mean(window_temps)
        sigma = statistics.stdev(window_temps)
        z = abs(row['temperature'] - mu) / max(sigma, 0.01)
        if z > 3.0:
            anomalies.append({**row, 'z_score': f'{z:.2f}', 'type': 'temperature_outlier'})
            continue
    clean.append(row)

with open(f'device_{device_id}_clean.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=['timestamp', 'temperature', 'humidity', 'pressure'])
    w.writeheader()
    w.writerows(clean)

with open(f'device_{device_id}_anomalies.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=['timestamp', 'temperature', 'humidity', 'pressure', 'z_score', 'type'])
    w.writeheader()
    w.writerows(anomalies)
PYEOF
    """
}

// ---------------------------------------------------------------------------
//  Edge layer — per-device statistics
// ---------------------------------------------------------------------------

process EDGE_STATS {
    tag "device_${device_id}"
    container 'python:3.12'

    input:
    tuple val(device_id), path(clean_data), path(anomaly_data)

    output:
    path "device_${device_id}_stats.json"

    script:
    """
    python3 << 'PYEOF'
import csv, json, statistics

device_id = ${device_id}

temps, humids, pressures = [], [], []
with open('${clean_data}') as f:
    for row in csv.DictReader(f):
        temps.append(float(row['temperature']))
        humids.append(float(row['humidity']))
        pressures.append(float(row['pressure']))

anomaly_count = 0
with open('${anomaly_data}') as f:
    anomaly_count = sum(1 for _ in csv.DictReader(f))

def summarise(values):
    return {'min': round(min(values), 2),
            'max': round(max(values), 2),
            'mean': round(statistics.mean(values), 2),
            'stdev': round(statistics.stdev(values), 2) if len(values) > 1 else 0,
            'count': len(values)}

result = {'device_id': device_id,
          'readings_clean': len(temps),
          'anomalies_detected': anomaly_count,
          'temperature': summarise(temps),
          'humidity': summarise(humids),
          'pressure': summarise(pressures)}

with open(f'device_{device_id}_stats.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF
    """
}

// ---------------------------------------------------------------------------
//  Cloud layer — cross-device aggregation and analytics
// ---------------------------------------------------------------------------

process CLOUD_AGGREGATE {
    container 'python:3.12'
    publishDir params.outdir, mode: 'copy'

    input:
    path stats_files

    output:
    path "iot_report.json"
    path "iot_dashboard.txt"

    script:
    """
    python3 << 'PYEOF'
import json, glob, statistics

devices = []
for path in sorted(glob.glob('device_*_stats.json')):
    with open(path) as fh:
        devices.append(json.load(fh))

temp_means = [d['temperature']['mean'] for d in devices]
humid_means = [d['humidity']['mean'] for d in devices]
press_means = [d['pressure']['mean'] for d in devices]
total_anomalies = sum(d['anomalies_detected'] for d in devices)
total_readings = sum(d['readings_clean'] for d in devices)
total_all = total_readings + total_anomalies

report = {
    'num_devices': len(devices),
    'total_readings_clean': total_readings,
    'total_anomalies': total_anomalies,
    'anomaly_rate_pct': round(total_anomalies / total_all * 100, 2) if total_all else 0,
    'system_temperature': {
        'mean': round(statistics.mean(temp_means), 2),
        'stdev_across_devices': round(statistics.stdev(temp_means), 2) if len(temp_means) > 1 else 0,
    },
    'system_humidity': {
        'mean': round(statistics.mean(humid_means), 2),
        'stdev_across_devices': round(statistics.stdev(humid_means), 2) if len(humid_means) > 1 else 0,
    },
    'system_pressure': {
        'mean': round(statistics.mean(press_means), 2),
        'stdev_across_devices': round(statistics.stdev(press_means), 2) if len(press_means) > 1 else 0,
    },
    'per_device': devices,
}

with open('iot_report.json', 'w') as f:
    json.dump(report, f, indent=2)

lines = [
    'IoT Sensor Network  -  Analytics Dashboard',
    '=' * 55,
    '',
    f"Devices:          {len(devices)}",
    f"Readings (clean): {total_readings:,}",
    f"Anomalies:        {total_anomalies:,}  ({report['anomaly_rate_pct']}%)",
    '',
    'System-wide averages:',
    f"  Temperature:  {report['system_temperature']['mean']:.1f} C   (cross-device sigma={report['system_temperature']['stdev_across_devices']:.2f})",
    f"  Humidity:     {report['system_humidity']['mean']:.1f} %   (cross-device sigma={report['system_humidity']['stdev_across_devices']:.2f})",
    f"  Pressure:     {report['system_pressure']['mean']:.1f} hPa (cross-device sigma={report['system_pressure']['stdev_across_devices']:.2f})",
    '',
    f"{'Device':<12} {'Clean':>7} {'Anom':>6} {'T mean':>7} {'T sig':>6} {'H mean':>7} {'P mean':>7}",
    '-' * 55,
]
for d in devices:
    lines.append(
        f"device_{d['device_id']:<5} {d['readings_clean']:>7} {d['anomalies_detected']:>6}"
        f" {d['temperature']['mean']:>7.1f} {d['temperature']['stdev']:>6.2f}"
        f" {d['humidity']['mean']:>7.1f} {d['pressure']['mean']:>7.1f}"
    )

with open('iot_dashboard.txt', 'w') as f:
    f.write('\\n'.join(lines) + '\\n')
PYEOF
    """
}

// ---------------------------------------------------------------------------
//  Workflow
// ---------------------------------------------------------------------------

workflow {
    devices_ch = Channel.of(1..(params.num_devices as int))

    SIMULATE_SENSORS(devices_ch)
    EDGE_PREPROCESS(SIMULATE_SENSORS.out)
    EDGE_STATS(EDGE_PREPROCESS.out)
    CLOUD_AGGREGATE(EDGE_STATS.out.collect())
}
