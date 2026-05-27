// Downloads CHM13v2 T2T FASTA from UCSC (hs1) and builds BWA + samtools index.
// Runs at most once per outdir — storeDir caches outputs across reruns.
process DOWNLOAD_REFERENCE {
    storeDir "${params.outdir}/_ref_cache/t2t"

    output:
    path "chm13v2.0.fa",                           emit: fasta
    path "chm13v2.0.fa.{amb,ann,bwt,pac,sa,fai}", emit: index

    stub:
    """
    touch chm13v2.0.fa chm13v2.0.fa.amb chm13v2.0.fa.ann \
          chm13v2.0.fa.bwt chm13v2.0.fa.pac chm13v2.0.fa.sa chm13v2.0.fa.fai
    """

    script:
    """
    curl -L https://hgdownload.soe.ucsc.edu/goldenPath/hs1/bigZips/hs1.fa.gz \
        | gzip -d > chm13v2.0.fa
    bwa index chm13v2.0.fa
    samtools faidx chm13v2.0.fa
    """
}

// Downloads the two PathSeq host index files from the public GATK GCS bucket
// into a hostdir/ subdirectory so qcfilter can use --hostdir <dir>.
process DOWNLOAD_HOST_INDEX {
    storeDir "${params.outdir}/_ref_cache/pathseq_host"

    output:
    path "hostdir", emit: dir

    stub:
    """
    mkdir -p hostdir
    touch hostdir/pathseq_host.bfi hostdir/pathseq_host.fa.img
    """

    script:
    """
    mkdir -p hostdir
    curl -L https://storage.googleapis.com/gatk-best-practices/pathseq/resources/pathseq_host.bfi \
        -o hostdir/pathseq_host.bfi
    curl -L https://storage.googleapis.com/gatk-best-practices/pathseq/resources/pathseq_host.fa.img \
        -o hostdir/pathseq_host.fa.img
    """
}

// Downloads and extracts a pre-built Kraken2 database tarball.
// Default is the standard-8GB DB; override with --kraken_db_url for a larger one.
// DB options: https://benlangmead.github.io/aws-indexes/k2
process DOWNLOAD_KRAKEN_DB {
    storeDir "${params.outdir}/_ref_cache/kraken2"

    output:
    path "db", emit: dir

    stub:
    """
    mkdir -p db
    touch db/hash.k2d db/opts.k2d db/taxo.k2d
    """

    script:
    """
    mkdir -p db
    curl -L ${params.kraken_db_url} | tar -xz -C db
    """
}
