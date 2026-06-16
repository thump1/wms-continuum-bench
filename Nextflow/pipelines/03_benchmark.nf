#!/usr/bin/env nextflow

/*
 * 03_benchmark.nf — Configurable benchmark pipeline for SWMS evaluation.
 *
 *   INGEST (fan-out) → PREPROCESS → ANALYZE → AGGREGATE (fan-in)
 *
 * Run:
 *   nextflow run pipelines/03_benchmark.nf -profile docker
 *   nextflow run pipelines/03_benchmark.nf -profile docker --num_chunks 20 --chunk_size_mb 100 --hash_rounds 1000
 */

params.num_chunks    = 10
params.chunk_size_mb = 25
params.hash_rounds   = 500
params.outdir        = "${projectDir}/../results/benchmark"

process INGEST {
    tag "chunk_${chunk_id}"
    container 'ubuntu:24.04'

    input:
    val chunk_id

    output:
    tuple val(chunk_id), path("chunk_${chunk_id}.dat")

    script:
    """
    dd if=/dev/urandom of=chunk_${chunk_id}.dat bs=1M count=${params.chunk_size_mb} 2>/dev/null
    """
}

process PREPROCESS {
    tag "chunk_${chunk_id}"
    container 'ubuntu:24.04'

    input:
    tuple val(chunk_id), path(raw)

    output:
    tuple val(chunk_id), path("chunk_${chunk_id}.gz")

    script:
    """
    gzip -c ${raw} > chunk_${chunk_id}.gz
    """
}

process ANALYZE {
    tag "chunk_${chunk_id}"
    container 'ubuntu:24.04'

    input:
    tuple val(chunk_id), path(data)

    output:
    path "analysis_${chunk_id}.tsv"

    script:
    """
    SIZE=\$(wc -c < ${data})
    HASH=\$(sha256sum ${data} | awk '{print \$1}')
    for i in \$(seq 2 ${params.hash_rounds}); do
        HASH=\$(echo -n "\$HASH" | sha256sum | awk '{print \$1}')
    done
    printf "%s\\t%s\\t%s\\t%s\\n" "${chunk_id}" "\$SIZE" "${params.hash_rounds}" "\$HASH" > analysis_${chunk_id}.tsv
    """
}

process AGGREGATE {
    container 'ubuntu:24.04'
    publishDir params.outdir, mode: 'copy'

    input:
    path analyses

    output:
    path "benchmark_report.txt"

    script:
    """
    {
      echo "Nextflow Benchmark Report"
      echo "Date:        \$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
      echo "Chunks:      ${params.num_chunks}"
      echo "Chunk size:  ${params.chunk_size_mb} MB"
      echo "Hash rounds: ${params.hash_rounds}"
      echo "Total data:  \$(( ${params.num_chunks} * ${params.chunk_size_mb} )) MB"
      echo ""
      printf "chunk_id\\tcompressed_bytes\\thash_rounds\\tfinal_hash\\n"
      cat analysis_*.tsv | sort -t\$'\\t' -k1 -n
    } > benchmark_report.txt
    """
}

workflow {
    chunks_ch = Channel.of(1..(params.num_chunks as int))

    INGEST(chunks_ch)
    PREPROCESS(INGEST.out)
    ANALYZE(PREPROCESS.out)
    AGGREGATE(ANALYZE.out.collect())
}
