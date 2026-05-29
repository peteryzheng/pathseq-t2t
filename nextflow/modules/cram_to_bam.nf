// Downloads the Broad/GATK GRCh38 bundle reference for CRAM decoding.
process DOWNLOAD_HG38 {
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

    input:
    tuple val(meta), path(cram)
    path hg38_ref
    path hg38_fai

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
