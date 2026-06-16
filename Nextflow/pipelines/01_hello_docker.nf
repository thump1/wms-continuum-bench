#!/usr/bin/env nextflow

/*
 * 01_hello_docker.nf
 * ------------------
 * Same hello-world, but each task runs inside an Ubuntu container.
 *
 * Demonstrates:
 *   - the `container` directive — task isolation, the foundation of
 *     reproducibility across HPC, cloud and edge in real SWMSs
 *   - capturing host kernel info from inside the container
 *
 * Run:
 *   nextflow run pipelines/01_hello_docker.nf -profile docker
 */

process SAYHELLO {
    container 'ubuntu:24.04'

    input:
    val name

    output:
    stdout

    script:
    """
    echo "Hello, ${name}, running inside Ubuntu container"
    echo "  kernel:    \$(uname -r)"
    echo "  hostname:  \$(hostname)"
    echo "  date:      \$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    """
}

workflow {
    Channel.of('Eduardo', 'Katja', 'Salvador', 'Pedro')
        | SAYHELLO
        | view
}
