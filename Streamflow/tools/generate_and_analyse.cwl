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
      head -c $(inputs.size) /dev/urandom > $(inputs.sample_id).dat && python3 -c "
      import hashlib, os, sys
      sid = '$(inputs.sample_id)'
      dat = sid + '.dat'
      length = os.path.getsize(dat)
      sha = hashlib.sha256(open(dat,'rb').read()).hexdigest()
      with open(sid + '_stats.txt', 'w') as f:
          f.write('sample_id=' + sid + chr(10))
          f.write('length=' + str(length) + chr(10))
          f.write('sha256=' + sha + chr(10))
      "

outputs:
  data_file:
    type: File
    outputBinding:
      glob: "*.dat"
  stats_file:
    type: File
    outputBinding:
      glob: "*_stats.txt"
