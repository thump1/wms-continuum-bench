cwlVersion: v1.2
class: Workflow

requirements:
  ScatterFeatureRequirement: {}
  InlineJavascriptRequirement: {}

inputs:
  num_devices:
    type: int
    default: 10
  readings_per_device:
    type: int
    default: 10000
  anomaly_rate:
    type: float
    default: 0.02
  transfer_latency_ms:
    type: int
    default: 0

steps:
  generate_device_ids:
    run:
      class: ExpressionTool
      requirements:
        InlineJavascriptRequirement: {}
      inputs:
        num_devices:
          type: int
      outputs:
        device_ids:
          type: int[]
      expression: |
        ${
          var ids = [];
          for (var i = 1; i <= inputs.num_devices; i++) {
            ids.push(i);
          }
          return {"device_ids": ids};
        }
    in:
      num_devices: num_devices
    out: [device_ids]

  device_pipeline:
    run: ../tools/device_pipeline_latency.cwl
    scatter: device_id
    in:
      device_id: generate_device_ids/device_ids
      readings_per_device: readings_per_device
      anomaly_rate: anomaly_rate
      transfer_latency_ms: transfer_latency_ms
    out: [stats_file]

  cloud_aggregate:
    run: ../tools/cloud_aggregate.cwl
    in:
      stats_files: device_pipeline/stats_file
    out: [report, dashboard]

outputs:
  report:
    type: File
    outputSource: cloud_aggregate/report
  dashboard:
    type: File
    outputSource: cloud_aggregate/dashboard
