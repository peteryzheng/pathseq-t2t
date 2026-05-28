process BINCLASSIFY {
    tag "${meta.id}"

    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(assembly_dir)

    output:
    tuple val(meta), path("assembly/${meta.id}"), emit: complete

    stub:
    """
    mkdir -p assembly/${meta.id}/gtdbtk_output
    touch assembly/${meta.id}/gtdbtk_output/gtdbtk.bac120.summary.tsv
    """

    script:
    def gtdbtk_env = params.gtdbtk_data ? "GTDBTK_DATA_PATH=${params.gtdbtk_data}" : ""
    """
    $gtdbtk_env pathseq-t2t binclassify \\
        --sample-id ${meta.id} \\
        --outdir . \\
        --threads $task.cpus
    """
}
