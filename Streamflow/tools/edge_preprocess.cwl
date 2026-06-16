cwlVersion: v1.2
class: CommandLineTool

requirements:
  ShellCommandRequirement: {}

baseCommand: []

inputs:
  device_id:
    type: int
  raw_data:
    type: File

arguments:
  - shellQuote: false
    valueFrom: |
      python3 << 'PYEOF'
      import csv, math, statistics

      device_id = $(inputs.device_id)
      WINDOW = 100

      rows = []
      with open('$(inputs.raw_data.basename)') as f:
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

outputs:
  clean_data:
    type: File
    outputBinding:
      glob: "*_clean.csv"
  anomaly_data:
    type: File
    outputBinding:
      glob: "*_anomalies.csv"
