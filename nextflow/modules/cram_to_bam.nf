// Downloads the Broad/GATK GRCh38 bundle reference for CRAM decoding.
// Runs at most once per pipeline invocation; storeDir caches the result.
process DOWNLOAD_HG38 {
    storeDir "${params.outdir}/_ref_cache/hg38_gatk"

    input:
    val trigger

    output:
    path "hg38.fa",     emit: ref
    path "hg38.fa.fai", emit: fai
    path "hg38.dict",   emit: dict

    stub:
    """
    touch hg38.fa hg38.fa.fai hg38.dict
    """

    script:
    """
    base_url="https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0"
    curl -fL "\${base_url}/Homo_sapiens_assembly38.fasta" -o hg38.fa
    curl -fL "\${base_url}/Homo_sapiens_assembly38.fasta.fai" -o hg38.fa.fai
    curl -fL "\${base_url}/Homo_sapiens_assembly38.dict" -o hg38.dict
    """
}

process CRAM_TO_BAM {
    tag "${meta.id}"
    publishDir "${params.outdir}/${meta.id}/bams", mode: 'copy'

    input:
    tuple val(meta), path(cram)
    path hg38_ref

    output:
    tuple val(meta), path("${meta.id}.bam"),     emit: bam
    tuple val(meta), path("${meta.id}.bam.bai"), emit: bai

    stub:
    """
    touch ${meta.id}.bam ${meta.id}.bam.bai
    """

    script:
    """
    samtools view -@ ${task.cpus} -b -T ${hg38_ref} -o ${meta.id}.bam ${cram}
    samtools index ${meta.id}.bam
    """
}
