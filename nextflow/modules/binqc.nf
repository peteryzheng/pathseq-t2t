process BINQC {
    tag "$sample_id"

    publishDir "${params.outdir}/${sample_id}", mode: 'copy'

    input:
    tuple val(sample_id), path(assembly_dir)

    output:
    tuple val(sample_id), path("assembly/${sample_id}"), emit: complete

    stub:
    """
    mkdir -p assembly/${sample_id}/checkm2 assembly/${sample_id}/checkv
    touch assembly/${sample_id}/checkm2/quality_report.tsv
    """

    script:
    def checkv_arg = params.checkv_db ? "--checkv-db ${params.checkv_db}" : ""
    """
    pathseq-t2t binqc \\
        --sample-id $sample_id \\
        --outdir . \\
        --threads $task.cpus \\
        $checkv_arg
    """
}
