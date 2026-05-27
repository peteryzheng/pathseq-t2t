process BINCLASSIFY {
    tag "$sample_id"

    publishDir "${params.outdir}/${sample_id}", mode: 'copy'

    input:
    tuple val(sample_id), path(assembly_dir)

    output:
    tuple val(sample_id), path("assembly/${sample_id}"), emit: complete

    stub:
    """
    mkdir -p assembly/${sample_id}/gtdbtk_output
    touch assembly/${sample_id}/gtdbtk_output/gtdbtk.bac120.summary.tsv
    """

    script:
    def gtdbtk_env = params.gtdbtk_data ? "GTDBTK_DATA_PATH=${params.gtdbtk_data}" : ""
    """
    $gtdbtk_env pathseq-t2t binclassify \\
        --sample-id $sample_id \\
        --outdir . \\
        --threads $task.cpus
    """
}
