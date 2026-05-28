process SUMMARIZE_ASSEMBLY {
    tag "${meta.id}"

    publishDir "${params.outdir}/${meta.id}/results", mode: 'copy'

    input:
    // Staged assembly_dir contains outputs from ASSEMBLE, BINQC, and BINCLASSIFY.
    // The three path inputs establish DAG dependencies on all three upstream processes.
    tuple val(meta),
          path(assembly_dir_assemble),
          path(assembly_dir_binqc),
          path(assembly_dir_binclassify)

    output:
    tuple val(meta), path("${meta.id}.assembly_summary.tsv"), emit: summary
    tuple val(meta), path("${meta.id}.bin_summary.tsv"),      emit: bin_summary, optional: true

    stub:
    """
    touch ${meta.id}.assembly_summary.tsv
    touch ${meta.id}.bin_summary.tsv
    """

    script:
    """
    pathseq-t2t summarize-assembly \\
        --sample-id ${meta.id} \\
        --assembly-dir $assembly_dir_assemble \\
        --results-dir .
    """
}
