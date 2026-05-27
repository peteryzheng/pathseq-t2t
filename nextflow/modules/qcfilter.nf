process QCFILTER {
    tag "$sample_id"

    publishDir "${params.outdir}/${sample_id}", mode: 'copy'

    input:
    tuple val(sample_id), path(unaligned_bam), path(decoys_bam)
    path hostdir

    output:
    tuple val(sample_id), path("bams/${sample_id}.qcfilt_paired.bam"),   emit: paired
    tuple val(sample_id), path("bams/${sample_id}.qcfilt_unpaired.bam"), emit: unpaired
    tuple val(sample_id), path("filter_stats/${sample_id}.prefilter.unaligned.filter_metrics.txt"), emit: metrics_unaligned
    tuple val(sample_id), path("filter_stats/${sample_id}.prefilter.decoys.filter_metrics.txt"),    emit: metrics_decoys

    stub:
    """
    mkdir -p bams filter_stats
    touch bams/${sample_id}.qcfilt_paired.bam
    touch bams/${sample_id}.qcfilt_unpaired.bam
    touch filter_stats/${sample_id}.prefilter.unaligned.filter_metrics.txt
    touch filter_stats/${sample_id}.prefilter.decoys.filter_metrics.txt
    """

    script:
    def ram = task.memory.toGiga() as int
    """
    pathseq-t2t qcfilter \\
        --input-unaligned $unaligned_bam \\
        --input-decoys    $decoys_bam \\
        --sample-id $sample_id \\
        --outdir . \\
        --hostdir ${hostdir} \\
        --threads $task.cpus \\
        --ram-gb $ram
    """
}
