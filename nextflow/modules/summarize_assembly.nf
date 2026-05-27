process SUMMARIZE_ASSEMBLY {
    tag "$sample_id"

    publishDir "${params.outdir}/${sample_id}/results", mode: 'copy'

    input:
    // Staged assembly_dir contains outputs from ASSEMBLE, BINQC, and BINCLASSIFY.
    // The three path inputs establish DAG dependencies on all three upstream processes.
    tuple val(sample_id),
          path(assembly_dir_assemble),
          path(assembly_dir_binqc),
          path(assembly_dir_binclassify)

    output:
    tuple val(sample_id), path("${sample_id}.assembly_summary.tsv"), emit: summary
    tuple val(sample_id), path("${sample_id}.bin_summary.tsv"),      emit: bin_summary, optional: true

    stub:
    """
    touch ${sample_id}.assembly_summary.tsv
    touch ${sample_id}.bin_summary.tsv
    """

    script:
    """
    pathseq-t2t summarize-assembly \\
        --sample-id $sample_id \\
        --assembly-dir $assembly_dir_assemble \\
        --results-dir .
    """
}
