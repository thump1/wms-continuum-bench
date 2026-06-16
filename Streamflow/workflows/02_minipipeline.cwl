cwlVersion: v1.2
class: Workflow

requirements:
  ScatterFeatureRequirement: {}

inputs:
  sample_ids:
    type: string[]
    default: ["sample_a", "sample_b", "sample_c", "sample_d", "sample_e"]
  sizes:
    type: int[]
    default: [1024, 2048, 512, 4096, 8192]

steps:
  generate_and_analyse:
    run: ../tools/generate_and_analyse.cwl
    scatter: [sample_id, size]
    scatterMethod: dotproduct
    in:
      sample_id: sample_ids
      size: sizes
    out: [data_file, stats_file]

  summarise:
    run: ../tools/summarise.cwl
    in:
      stats_files: generate_and_analyse/stats_file
    out: [summary]

outputs:
  data_files:
    type: File[]
    outputSource: generate_and_analyse/data_file
  summary:
    type: File
    outputSource: summarise/summary
