process ASSEMBLE {
    tag "${meta.id}"

    input:
    tuple val(meta), path(unaligned_bam), path(decoys_bam)

    output:
    tuple val(meta), path("assembly/${meta.id}"), emit: dir

    stub:
    """
    mkdir -p assembly/${meta.id}/metabat2_bins
    touch assembly/${meta.id}/final.contigs.fa
    """

    script:
    """
    pathseq-t2t assemble \\
        --input-unaligned $unaligned_bam \\
        --input-decoys    $decoys_bam \\
        --sample-id ${meta.id} \\
        --outdir . \\
        --threads $task.cpus
    """
}
