cwlVersion: v1.2
class: CommandLineTool

requirements:
  ShellCommandRequirement: {}

baseCommand: []

inputs:
  device_id:
    type: int
  clean_data:
    type: File
  anomaly_data:
    type: File

arguments:
  - shellQuote: false
    valueFrom: |
      python3 << 'PYEOF'
      import csv, json, statistics

      device_id = $(inputs.device_id)

      temps, humids, pressures = [], [], []
      with open('$(inputs.clean_data.basename)') as f:
          for row in csv.DictReader(f):
              temps.append(float(row['temperature']))
              humids.append(float(row['humidity']))
              pressures.append(float(row['pressure']))

      anomaly_count = 0
      with open('$(inputs.anomaly_data.basename)') as f:
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

outputs:
  stats_file:
    type: File
    outputBinding:
      glob: "*_stats.json"
