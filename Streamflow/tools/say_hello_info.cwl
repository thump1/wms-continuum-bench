cwlVersion: v1.2
class: CommandLineTool

requirements:
  ShellCommandRequirement: {}

baseCommand: []

inputs:
  name:
    type: string

arguments:
  - shellQuote: false
    valueFrom: |
      {
        echo "Hello, $(inputs.name), running inside container"
        echo "  kernel:    \$(uname -r)"
        echo "  hostname:  \$(hostname)"
        echo "  date:      \$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
      } > greeting.txt

outputs:
  greeting:
    type: File
    outputBinding:
      glob: greeting.txt
