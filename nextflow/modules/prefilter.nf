process PREFILTER {
    tag "${meta.id}"

    input:
    tuple val(meta), path(bam)
    path decoys_bed

    output:
    tuple val(meta), path("bams/${meta.id}.prefilter.unaligned.bam"), emit: unaligned
    tuple val(meta), path("bams/${meta.id}.prefilter.decoys.bam"),    emit: decoys
    tuple val(meta), path("filter_stats/${meta.id}.flagstat.tsv"),    emit: flagstat

    stub:
    """
    mkdir -p bams filter_stats
    touch bams/${meta.id}.prefilter.unaligned.bam
    touch bams/${meta.id}.prefilter.decoys.bam
    touch filter_stats/${meta.id}.flagstat.tsv
    """

    script:
    def decoys_arg = decoys_bed.name != 'NO_FILE' ? "--decoys-to-mask ${decoys_bed}" : "--decoys-to-mask None"
    """
    pathseq-t2t prefilter \\
        --input-bam $bam \\
        --aligner ${params.aligner} \\
        $decoys_arg \\
        --sample-id ${meta.id} \\
        --outdir . \\
        --threads $task.cpus
    """
}
