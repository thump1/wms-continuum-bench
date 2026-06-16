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
      echo "Hello, $(inputs.name), from StreamFlow on Mac!" > greeting.txt

outputs:
  greeting:
    type: File
    outputBinding:
      glob: greeting.txt
