// Three separate processes so they run in parallel and have independent resource quotas.
// Each calls `pathseq-t2t classify --classifiers <single>` — BAM-to-FASTQ conversion
// is handled internally by the CLI.

process CLASSIFY_KRAKEN {
    tag "${meta.id}"

    input:
    tuple val(meta), path(paired_bam), path(unpaired_bam)
    path kraken_db

    output:
    tuple val(meta), path("classification_stats/${meta.id}.paired.kraken.report.txt"),   emit: report_paired
    tuple val(meta), path("classification_stats/${meta.id}.unpaired.kraken.report.txt"), emit: report_unpaired
    tuple val(meta), path("classification_stats/${meta.id}.paired.kraken.output.txt"),   emit: output_paired
    tuple val(meta), path("classification_stats/${meta.id}.unpaired.kraken.output.txt"), emit: output_unpaired

    stub:
    """
    mkdir -p classification_stats
    touch classification_stats/${meta.id}.paired.kraken.report.txt
    touch classification_stats/${meta.id}.unpaired.kraken.report.txt
    touch classification_stats/${meta.id}.paired.kraken.output.txt
    touch classification_stats/${meta.id}.unpaired.kraken.output.txt
    """

    script:
    """
    pathseq-t2t classify \\
        --classifiers kraken \\
        --input-paired   $paired_bam \\
        --input-unpaired $unpaired_bam \\
        --sample-id ${meta.id} \\
        --outdir . \\
        --kraken-index ${kraken_db} \\
        --threads $task.cpus
    """
}

process CLASSIFY_METAPHLAN {
    tag "${meta.id}"

    input:
    tuple val(meta), path(paired_bam), path(unpaired_bam)
    path bowtie2_db

    output:
    tuple val(meta), path("classification_stats/${meta.id}.metaphlan.report.txt"), emit: report

    stub:
    """
    mkdir -p classification_stats
    touch classification_stats/${meta.id}.metaphlan.report.txt
    """

    script:
    """
    pathseq-t2t classify \\
        --classifiers metaphlan \\
        --input-paired   $paired_bam \\
        --input-unpaired $unpaired_bam \\
        --sample-id ${meta.id} \\
        --outdir . \\
        --metaphlan-index ${params.metaphlan_index} \\
        --bowtie2-index   ${bowtie2_db} \\
        --threads $task.cpus
    """
}

process CLASSIFY_SYLPH {
    tag "${meta.id}"

    input:
    tuple val(meta), path(paired_bam), path(unpaired_bam)
    path sylph_db

    output:
    tuple val(meta), path("classification_stats/${meta.id}.paired.sylph.report.txt"),   emit: report_paired
    tuple val(meta), path("classification_stats/${meta.id}.unpaired.sylph.report.txt"), emit: report_unpaired

    stub:
    """
    mkdir -p classification_stats
    touch classification_stats/${meta.id}.paired.sylph.report.txt
    touch classification_stats/${meta.id}.unpaired.sylph.report.txt
    """

    script:
    def tax_arg = params.sylph_taxonomy ? "--sylph-taxonomy ${params.sylph_taxonomy}" : ""
    """
    pathseq-t2t classify \\
        --classifiers sylph \\
        --input-paired   $paired_bam \\
        --input-unpaired $unpaired_bam \\
        --sample-id ${meta.id} \\
        --outdir . \\
        --sylph-index ${sylph_db} \\
        $tax_arg \\
        --threads $task.cpus
    """
}
