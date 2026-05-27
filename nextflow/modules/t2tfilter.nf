process T2TFILTER {
    tag "$sample_id"

    publishDir "${params.outdir}/${sample_id}", mode: 'copy'

    input:
    tuple val(sample_id), path(paired_bam), path(unpaired_bam)
    path reference
    path ref_index

    output:
    tuple val(sample_id), path("bams/${sample_id}.t2tfilt_paired.bam"),   emit: paired
    tuple val(sample_id), path("bams/${sample_id}.t2tfilt_unpaired.bam"), emit: unpaired
    tuple val(sample_id), path("filter_stats/${sample_id}.t2tfilt_paired.t2t_unaln.flagstat.tsv"),   emit: flagstat_paired
    tuple val(sample_id), path("filter_stats/${sample_id}.t2tfilt_unpaired.t2t_unaln.flagstat.tsv"), emit: flagstat_unpaired

    stub:
    """
    mkdir -p bams filter_stats
    touch bams/${sample_id}.t2tfilt_paired.bam
    touch bams/${sample_id}.t2tfilt_unpaired.bam
    touch filter_stats/${sample_id}.t2tfilt_paired.t2t_unaln.flagstat.tsv
    touch filter_stats/${sample_id}.t2tfilt_unpaired.t2t_unaln.flagstat.tsv
    """

    script:
    def decoys_arg = params.decoys_bed ? "--decoys-to-mask ${params.decoys_bed}" : ""
    """
    pathseq-t2t t2tfilter \\
        --input-paired   $paired_bam \\
        --input-unpaired $unpaired_bam \\
        --sample-id $sample_id \\
        --outdir . \\
        --reference ${reference} \\
        $decoys_arg \\
        --threads $task.cpus
    """
}
