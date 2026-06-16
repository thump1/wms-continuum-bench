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
      {
        echo "Mini-pipeline summary"
        echo "Generated:  \$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        echo "Samples:    \$(ls -1 *_stats.txt | wc -l)"
        echo "----"
        cat *_stats.txt
      } > summary.txt

outputs:
  summary:
    type: File
    outputBinding:
      glob: summary.txt
