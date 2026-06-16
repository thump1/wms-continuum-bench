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
      import csv, random, math

      device_id = $(inputs.device_id)
      n = $(inputs.readings_per_device)
      anomaly_rate = $(inputs.anomaly_rate)

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

outputs:
  raw_data:
    type: File
    outputBinding:
      glob: "device_*.csv"
