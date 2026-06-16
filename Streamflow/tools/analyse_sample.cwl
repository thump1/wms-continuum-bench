cwlVersion: v1.2
class: CommandLineTool

requirements:
  ShellCommandRequirement: {}

baseCommand: []

inputs:
  sample_id:
    type: string
  data_file:
    type: File

arguments:
  - shellQuote: false
    valueFrom: |
      LEN=\$(wc -c < $(inputs.data_file.path))
      SHA=\$(sha256sum $(inputs.data_file.path) | awk '{print \$1}')
      echo "sample_id=$(inputs.sample_id)" > $(inputs.sample_id)_stats.txt
      echo "length=\$LEN" >> $(inputs.sample_id)_stats.txt
      echo "sha256=\$SHA" >> $(inputs.sample_id)_stats.txt

outputs:
  stats_file:
    type: File
    outputBinding:
      glob: "*_stats.txt"
