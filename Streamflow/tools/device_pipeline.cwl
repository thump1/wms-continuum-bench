cwlVersion: v1.2
class: CommandLineTool

requirements:
  ShellCommandRequirement: {}

baseCommand: []

inputs:
  device_id:
    type: int
  readings_per_device:
    type: int
    default: 10000
  anomaly_rate:
    type: float
    default: 0.02

arguments:
  - shellQuote: false
    valueFrom: |
      python3 << 'PYEOF'
      import csv, random, math, statistics, json

      device_id = $(inputs.device_id)
      n = $(inputs.readings_per_device)
      anomaly_rate = $(inputs.anomaly_rate)

      # --- Stage 1: Simulate sensors ---
      random.seed(device_id * 31337)
      temp_base = 22.0 + random.uniform(-2, 2)
      humidity_base = 60.0 + random.uniform(-5, 5)
      pressure_base = 1013.0 + random.uniform(-3, 3)

      raw_rows = []
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
          raw_rows.append({'timestamp': i, 'temperature': temp,
                           'humidity': humidity, 'pressure': pressure})

      with open(f'device_{device_id}.csv', 'w', newline='') as f:
          w = csv.DictWriter(f, fieldnames=['timestamp','temperature','humidity','pressure'])
          w.writeheader()
          for r in raw_rows:
              w.writerow({k: (f'{v:.2f}' if isinstance(v,float) else v) for k,v in r.items()})

      # --- Stage 2: Edge preprocessing (z-score anomaly detection) ---
      WINDOW = 100
      valid = [r for r in raw_rows
               if not (math.isnan(r['temperature']) or math.isnan(r['humidity'])
                       or math.isnan(r['pressure']))]

      clean, anomalies = [], []
      for i, row in enumerate(valid):
          start = max(0, i - WINDOW)
          window_temps = [r['temperature'] for r in valid[start:i+1]]
          if len(window_temps) >= 3:
              mu = statistics.mean(window_temps)
              sigma = statistics.stdev(window_temps)
              z = abs(row['temperature'] - mu) / max(sigma, 0.01)
              if z > 3.0:
                  anomalies.append({**row, 'z_score': round(z,2), 'type': 'temperature_outlier'})
                  continue
          clean.append(row)

      with open(f'device_{device_id}_clean.csv', 'w', newline='') as f:
          w = csv.DictWriter(f, fieldnames=['timestamp','temperature','humidity','pressure'])
          w.writeheader()
          for r in clean:
              w.writerow({k: (f'{v:.2f}' if isinstance(v,float) else v) for k,v in r.items()})

      with open(f'device_{device_id}_anomalies.csv', 'w', newline='') as f:
          w = csv.DictWriter(f, fieldnames=['timestamp','temperature','humidity','pressure','z_score','type'])
          w.writeheader()
          for r in anomalies:
              w.writerow({k: (f'{v:.2f}' if isinstance(v,float) else v) for k,v in r.items()})

      # --- Stage 3: Edge stats ---
      temps = [r['temperature'] for r in clean]
      humids = [r['humidity'] for r in clean]
      pressures = [r['pressure'] for r in clean]

      def summarise(values):
          return {'min': round(min(values),2), 'max': round(max(values),2),
                  'mean': round(statistics.mean(values),2),
                  'stdev': round(statistics.stdev(values),2) if len(values)>1 else 0,
                  'count': len(values)}

      result = {'device_id': device_id,
                'readings_clean': len(temps),
                'anomalies_detected': len(anomalies),
                'temperature': summarise(temps),
                'humidity': summarise(humids),
                'pressure': summarise(pressures)}

      with open(f'device_{device_id}_stats.json', 'w') as f:
          json.dump(result, f, indent=2)
      PYEOF

outputs:
  raw_data:
    type: File
    outputBinding:
      glob: "device_*[!_]*.csv"
  clean_data:
    type: File
    outputBinding:
      glob: "*_clean.csv"
  anomaly_data:
    type: File
    outputBinding:
      glob: "*_anomalies.csv"
  stats_file:
    type: File
    outputBinding:
      glob: "*_stats.json"
