// Downloads hg38 from UCSC and indexes it. Runs at most once per pipeline
// invocation; storeDir caches the result so re-runs skip the download.
process DOWNLOAD_HG38 {
    storeDir "${params.outdir}/_ref_cache/hg38"

    input:
    val trigger

    output:
    path "hg38.fa",     emit: ref
    path "hg38.fa.fai", emit: fai

    stub:
    """
    touch hg38.fa hg38.fa.fai
    """

    script:
    """
    curl -L https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz \
        | gzip -d > hg38.fa
    samtools faidx hg38.fa
    """
}

process CRAM_TO_BAM {
    tag "$sample_id"
    publishDir "${params.outdir}/${sample_id}/bams", mode: 'copy'

    input:
    tuple val(sample_id), path(cram)
    path hg38_ref

    output:
    tuple val(sample_id), path("${sample_id}.bam"),     emit: bam
    tuple val(sample_id), path("${sample_id}.bam.bai"), emit: bai

    stub:
    """
    touch ${sample_id}.bam ${sample_id}.bam.bai
    """

    script:
    """
    samtools view -@ ${task.cpus} -b -T ${hg38_ref} -o ${sample_id}.bam ${cram}
    samtools index ${sample_id}.bam
    """
}
