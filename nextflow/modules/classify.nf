// Three separate processes so they run in parallel and have independent resource quotas.
// Each calls `pathseq-t2t classify --classifiers <single>` — BAM-to-FASTQ conversion
// is handled internally by the CLI.

process CLASSIFY_KRAKEN {
    tag "$sample_id"

    publishDir "${params.outdir}/${sample_id}", mode: 'copy'

    input:
    tuple val(sample_id), path(paired_bam), path(unpaired_bam)

    output:
    tuple val(sample_id), path("classification_stats/${sample_id}.paired.kraken.report.txt"),   emit: report_paired
    tuple val(sample_id), path("classification_stats/${sample_id}.unpaired.kraken.report.txt"), emit: report_unpaired

    stub:
    """
    mkdir -p classification_stats
    touch classification_stats/${sample_id}.paired.kraken.report.txt
    touch classification_stats/${sample_id}.unpaired.kraken.report.txt
    """

    script:
    """
    pathseq-t2t classify \\
        --classifiers kraken \\
        --input-paired   $paired_bam \\
        --input-unpaired $unpaired_bam \\
        --sample-id $sample_id \\
        --outdir . \\
        --kraken-index ${params.kraken_index} \\
        --threads $task.cpus
    """
}

process CLASSIFY_METAPHLAN {
    tag "$sample_id"

    publishDir "${params.outdir}/${sample_id}", mode: 'copy'

    input:
    tuple val(sample_id), path(paired_bam), path(unpaired_bam)

    output:
    tuple val(sample_id), path("classification_stats/${sample_id}.metaphlan.report.txt"), emit: report

    stub:
    """
    mkdir -p classification_stats
    touch classification_stats/${sample_id}.metaphlan.report.txt
    """

    script:
    """
    pathseq-t2t classify \\
        --classifiers metaphlan \\
        --input-paired   $paired_bam \\
        --input-unpaired $unpaired_bam \\
        --sample-id $sample_id \\
        --outdir . \\
        --metaphlan-index ${params.metaphlan_index} \\
        --bowtie2-index   ${params.bowtie2_index} \\
        --threads $task.cpus
    """
}

process CLASSIFY_SYLPH {
    tag "$sample_id"

    publishDir "${params.outdir}/${sample_id}", mode: 'copy'

    input:
    tuple val(sample_id), path(paired_bam), path(unpaired_bam)

    output:
    tuple val(sample_id), path("classification_stats/${sample_id}.paired.taxonomy.txt"),   emit: report_paired
    tuple val(sample_id), path("classification_stats/${sample_id}.unpaired.taxonomy.txt"), emit: report_unpaired

    stub:
    """
    mkdir -p classification_stats
    touch classification_stats/${sample_id}.paired.taxonomy.txt
    touch classification_stats/${sample_id}.unpaired.taxonomy.txt
    """

    script:
    def tax_arg = params.sylph_taxonomy ? "--sylph-taxonomy ${params.sylph_taxonomy}" : ""
    """
    pathseq-t2t classify \\
        --classifiers sylph \\
        --input-paired   $paired_bam \\
        --input-unpaired $unpaired_bam \\
        --sample-id $sample_id \\
        --outdir . \\
        --sylph-index ${params.sylph_index} \\
        $tax_arg \\
        --threads $task.cpus
    """
}
