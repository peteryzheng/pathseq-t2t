process QCFILTER {
    tag "${meta.id}"

    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(unaligned_bam), path(decoys_bam)
    path hostdir

    output:
    tuple val(meta), path("bams/${meta.id}.qcfilt_paired.bam"),   emit: paired
    tuple val(meta), path("bams/${meta.id}.qcfilt_unpaired.bam"), emit: unpaired
    tuple val(meta), path("filter_stats/${meta.id}.prefilter.unaligned.filter_metrics.txt"), emit: metrics_unaligned
    tuple val(meta), path("filter_stats/${meta.id}.prefilter.decoys.filter_metrics.txt"),    emit: metrics_decoys

    stub:
    """
    mkdir -p bams filter_stats
    touch bams/${meta.id}.qcfilt_paired.bam
    touch bams/${meta.id}.qcfilt_unpaired.bam
    touch filter_stats/${meta.id}.prefilter.unaligned.filter_metrics.txt
    touch filter_stats/${meta.id}.prefilter.decoys.filter_metrics.txt
    """

    script:
    def ram = task.memory.toGiga() as int
    """
    pathseq-t2t qcfilter \\
        --input-unaligned $unaligned_bam \\
        --input-decoys    $decoys_bam \\
        --sample-id ${meta.id} \\
        --outdir . \\
        --hostdir ${hostdir} \\
        --threads $task.cpus \\
        --ram-gb $ram
    """
}
