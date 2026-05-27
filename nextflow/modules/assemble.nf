process ASSEMBLE {
    tag "$sample_id"

    publishDir "${params.outdir}/${sample_id}", mode: 'copy'

    input:
    tuple val(sample_id), path(unaligned_bam), path(decoys_bam)

    output:
    tuple val(sample_id), path("assembly/${sample_id}"), emit: dir

    stub:
    """
    mkdir -p assembly/${sample_id}/metabat2_bins
    touch assembly/${sample_id}/final.contigs.fa
    """

    script:
    """
    pathseq-t2t assemble \\
        --input-unaligned $unaligned_bam \\
        --input-decoys    $decoys_bam \\
        --sample-id $sample_id \\
        --outdir . \\
        --threads $task.cpus
    """
}
