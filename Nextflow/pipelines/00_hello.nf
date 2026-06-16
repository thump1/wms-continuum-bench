#!/usr/bin/env nextflow

/*
 * 00_hello.nf
 * -----------
 * Minimal Nextflow pipeline — no containers, runs natively on the host.
 *
 * Demonstrates:
 *   - a single process with a string input and stdout output
 *   - a channel of values created from a Groovy list
 *   - pipe operator (|) for chaining channels and processes
 *
 * Run:
 *   nextflow run pipelines/00_hello.nf
 */

process SAYHELLO {
    input:
    val name

    output:
    stdout

    script:
    """
    echo "Hello, ${name}, from Nextflow on Mac!"
    """
}

workflow {
    Channel.of('Eduardo', 'Katja', 'Salvador', 'Pedro')
        | SAYHELLO
        | view
}
