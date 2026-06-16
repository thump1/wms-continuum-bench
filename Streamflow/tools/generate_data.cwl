cwlVersion: v1.2
class: CommandLineTool

requirements:
  ShellCommandRequirement: {}

baseCommand: []

inputs:
  sample_id:
    type: string
  size:
    type: int

arguments:
  - shellQuote: false
    valueFrom: |
      head -c $(inputs.size) /dev/urandom > $(inputs.sample_id).dat

outputs:
  data_file:
    type: File
    outputBinding:
      glob: "*.dat"
