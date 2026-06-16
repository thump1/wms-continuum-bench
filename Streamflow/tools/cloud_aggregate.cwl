cwlVersion: v1.2
class: CommandLineTool

requirements:
  ShellCommandRequirement: {}
  InitialWorkDirRequirement:
    listing: $(inputs.stats_files)

baseCommand: []

inputs:
  stats_files:
    type: File[]

arguments:
  - shellQuote: false
    valueFrom: |
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
          f.write('\n'.join(lines) + '\n')
      PYEOF

outputs:
  report:
    type: File
    outputBinding:
      glob: iot_report.json
  dashboard:
    type: File
    outputBinding:
      glob: iot_dashboard.txt
