#!/usr/bin/env nextflow

/*
 * 02_minipipeline.nf
 * ------------------
 * Toy scientific workflow demonstrating a realistic multi-stage DAG.
 *
 *      GENERATE_DATA  →  ANALYSE_SAMPLE (one per sample)  →  SUMMARISE
 *                              [ fan-out ]                     [ fan-in ]
 *
 * Demonstrates:
 *   - reading parameters from a CSV file with splitCsv
 *   - tuple inputs (sample_id + payload)
 *   - parallel execution across samples (fan-out)
 *   - collecting outputs to feed a single downstream task (fan-in)
 *   - publishDir to copy results out of work/ into results/
 *   - container per process (heterogeneous workflows in practice would
 *     use different containers per stage)
 *
 * Inputs:
 *   data/samples.csv  (sample_id,size)
 *
 * Outputs:
 *   results/minipipeline/summary.txt
 *
 * Run:
 *   nextflow run pipelines/02_minipipeline.nf -profile docker
 */

params.samples_csv = "${projectDir}/../data/samples.csv"
params.outdir      = "${projectDir}/../results/minipipeline"

process GENERATE_DATA {
    tag "${sample_id}"
    container 'ubuntu:24.04'

    input:
    tuple val(sample_id), val(size)

    output:
    tuple val(sample_id), path("${sample_id}.dat")

    script:
    """
    # Pretend we are generating sample data of the requested size
    head -c ${size} /dev/urandom > ${sample_id}.dat
    """
}

process ANALYSE_SAMPLE {
    tag "${sample_id}"
    container 'ubuntu:24.04'

    input:
    tuple val(sample_id), path(data)

    output:
    path "${sample_id}_stats.txt"

    script:
    """
    LEN=\$(wc -c < ${data})
    SHA=\$(sha256sum ${data} | awk '{print \$1}')
    {
      echo "sample_id=${sample_id}"
      echo "length=\$LEN"
      echo "sha256=\$SHA"
      echo ""
    } > ${sample_id}_stats.txt
    """
}

process SUMMARISE {
    container 'ubuntu:24.04'
    publishDir params.outdir, mode: 'copy'

    input:
    path stats_files

    output:
    path "summary.txt"

    script:
    """
    {
      echo "Mini-pipeline summary"
      echo "Generated:  \$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
      echo "Samples:    \$(ls -1 *_stats.txt | wc -l)"
      echo "----"
      cat *_stats.txt
    } > summary.txt
    """
}

workflow {
    samples_ch = Channel
        .fromPath(params.samples_csv)
        .splitCsv(header: true)
        .map { row -> tuple(row.sample_id, row.size as Integer) }

    GENERATE_DATA(samples_ch)
    ANALYSE_SAMPLE(GENERATE_DATA.out)
    SUMMARISE(ANALYSE_SAMPLE.out.collect())
}
