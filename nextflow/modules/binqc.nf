process BINQC {
    tag "${meta.id}"

    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(assembly_dir)

    output:
    tuple val(meta), path("assembly/${meta.id}/checkm2"), emit: complete

    stub:
    """
    mkdir -p assembly/${meta.id}/checkm2
    touch assembly/${meta.id}/checkm2/quality_report.tsv
    """

    script:
    def checkv_arg = params.checkv_db
        ? "--checkv-db ${params.checkv_db}"
        : "--model checkm2"
    """
    pathseq-t2t binqc \\
        --sample-id ${meta.id} \\
        --assembly-dir $assembly_dir \\
        --outdir . \\
        --threads $task.cpus \\
        $checkv_arg
    """
}
