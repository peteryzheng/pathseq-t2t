process PREFILTER {
    tag "$sample_id"

    publishDir "${params.outdir}/${sample_id}", mode: 'copy'

    input:
    tuple val(sample_id), path(bam)

    output:
    tuple val(sample_id), path("bams/${sample_id}.prefilter.unaligned.bam"), emit: unaligned
    tuple val(sample_id), path("bams/${sample_id}.prefilter.decoys.bam"),    emit: decoys
    tuple val(sample_id), path("filter_stats/${sample_id}.flagstat.tsv"),    emit: flagstat

    stub:
    """
    mkdir -p bams filter_stats
    touch bams/${sample_id}.prefilter.unaligned.bam
    touch bams/${sample_id}.prefilter.decoys.bam
    touch filter_stats/${sample_id}.flagstat.tsv
    """

    script:
    def decoys_arg = params.decoys_bed ? "--decoys-to-mask ${params.decoys_bed}" : "--decoys-to-mask None"
    """
    pathseq-t2t prefilter \\
        --input-bam $bam \\
        --aligner ${params.aligner} \\
        $decoys_arg \\
        --sample-id $sample_id \\
        --outdir . \\
        --threads $task.cpus
    """
}
