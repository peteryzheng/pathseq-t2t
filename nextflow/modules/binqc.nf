process BINQC {
    tag "${meta.id}"

    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(assembly_dir)

    output:
    tuple val(meta), path("assembly/${meta.id}"), emit: complete

    stub:
    """
    mkdir -p assembly/${meta.id}/checkm2 assembly/${meta.id}/checkv
    touch assembly/${meta.id}/checkm2/quality_report.tsv
    """

    script:
    def checkv_arg = params.checkv_db ? "--checkv-db ${params.checkv_db}" : ""
    """
    pathseq-t2t binqc \\
        --sample-id ${meta.id} \\
        --outdir . \\
        --threads $task.cpus \\
        $checkv_arg
    """
}
