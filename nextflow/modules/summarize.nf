// Receives all filter stats and classifier reports as explicit path inputs so
// Nextflow stages them (from S3 or local) before the process runs.
// Classifier report lists are empty ([]) when the classifier was not run.

process SUMMARIZE {
    tag "$sample_id"

    publishDir "${params.outdir}/${sample_id}/results", mode: 'copy'

    input:
    tuple val(sample_id),
          path(flagstat),
          path(metrics_unaligned),
          path(metrics_decoys),
          path(t2t_flagstat_paired),
          path(t2t_flagstat_unpaired),
          path(kraken_reports),      // [] or [report_paired, report_unpaired]
          path(metaphlan_reports),   // [] or [report]
          path(sylph_reports)        // [] or [report_paired, report_unpaired]

    output:
    tuple val(sample_id), path("${sample_id}.summary.tsv"),    emit: summary
    tuple val(sample_id), path("${sample_id}.*.txt", arity: '0..*'), emit: classifier_tables, optional: true

    stub:
    """
    touch ${sample_id}.summary.tsv
    """

    script:
    def kraken_args = (kraken_reports instanceof List && kraken_reports.size() == 2)
        ? "--kraken-report-paired ${kraken_reports[0]} --kraken-report-unpaired ${kraken_reports[1]}"
        : (kraken_reports && !(kraken_reports instanceof List) ? "--kraken-report-paired ${kraken_reports}" : "")

    def metaphlan_args = (metaphlan_reports instanceof List && metaphlan_reports.size() == 1)
        ? "--metaphlan-report ${metaphlan_reports[0]}"
        : (metaphlan_reports && !(metaphlan_reports instanceof List) ? "--metaphlan-report ${metaphlan_reports}" : "")

    def sylph_args = (sylph_reports instanceof List && sylph_reports.size() == 2)
        ? "--sylph-report-paired ${sylph_reports[0]} --sylph-report-unpaired ${sylph_reports[1]}"
        : (sylph_reports && !(sylph_reports instanceof List) ? "--sylph-report-paired ${sylph_reports}" : "")

    """
    pathseq-t2t summarize \\
        --sample-id $sample_id \\
        --input-flagstat $flagstat \\
        --qcfilter-metrics-unaligned $metrics_unaligned \\
        --qcfilter-metrics-decoys    $metrics_decoys \\
        --t2tfilter-flagstat-paired   $t2t_flagstat_paired \\
        --t2tfilter-flagstat-unpaired $t2t_flagstat_unpaired \\
        --results-dir . \\
        $kraken_args \\
        $metaphlan_args \\
        $sylph_args
    """
}
