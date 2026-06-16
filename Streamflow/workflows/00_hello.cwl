cwlVersion: v1.2
class: Workflow

requirements:
  ScatterFeatureRequirement: {}

inputs:
  names:
    type: string[]
    default: ["Eduardo", "Katja", "Salvador", "Pedro"]

steps:
  say_hello:
    run: ../tools/say_hello.cwl
    scatter: name
    in:
      name: names
    out: [greeting]

outputs:
  greetings:
    type: File[]
    outputSource: say_hello/greeting
