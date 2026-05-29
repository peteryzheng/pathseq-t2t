nextflow.enable.dsl = 2

include { validateParameters } from 'plugin/nf-schema'

include { DOWNLOAD_HG38; CRAM_TO_BAM                                      } from './modules/cram_to_bam'
include { DOWNLOAD_REFERENCE; DOWNLOAD_HOST_INDEX; DOWNLOAD_KRAKEN_DB     } from './modules/download_refs'
include { SUMMARIZE          } from './modules/summarize'
include { SUMMARIZE_ASSEMBLY } from './modules/summarize_assembly'
include { FILTER             } from './subworkflows/local/filter'
include { CLASSIFY           } from './subworkflows/local/classify'
include { ASSEMBLE           } from './modules/assemble'
include { BINQC              } from './modules/binqc'
include { BINCLASSIFY        } from './modules/binclassify'

workflow {

    validateParameters()

    def classifiers = params.classifiers.tokenize(',')*.trim()*.toLowerCase()

    if ('metaphlan' in classifiers && !params.metaphlan_index) error "'metaphlan' in --classifiers but --metaphlan_index not set"
    if ('metaphlan' in classifiers && !params.bowtie2_index)   error "'metaphlan' in --classifiers but --bowtie2_index not set"
    if ('sylph'     in classifiers && !params.sylph_index)     error "'sylph' in --classifiers but --sylph_index not set"

    // ── Samplesheet ────────────────────────────────────────────────────────────
    ch_samples = Channel
        .fromPath(params.samplesheet, checkIfExists: true)
        .splitCsv(header: true)
        .map { row ->
            if (!row.sample_id) error "Samplesheet row missing 'sample_id' column"
            if (!row.bam)       error "Samplesheet row missing 'bam' column"
            def meta = [id: row.sample_id]
            tuple(meta, file(row.bam, checkIfExists: true))
        }

    // ── CRAM → BAM conversion (auto-detected by extension) ────────────────────
    ch_samples.branch {
        cram: it[1].name.endsWith('.cram')
        bam:  true
    }.set { ch_by_type }

    def ch_hg38_ref, ch_hg38_fai
    if (params.hg38_ref) {
        ch_hg38_ref = Channel.value(file(params.hg38_ref,          checkIfExists: true))
        ch_hg38_fai = Channel.value(file("${params.hg38_ref}.fai", checkIfExists: true))
    } else {
        def dl_hg38 = DOWNLOAD_HG38(ch_by_type.cram.first().map { "fetch" })
        ch_hg38_ref = dl_hg38.ref
        ch_hg38_fai = dl_hg38.fai
    }

    CRAM_TO_BAM(ch_by_type.cram, ch_hg38_ref, ch_hg38_fai)
    ch_inputs = ch_by_type.bam.mix(CRAM_TO_BAM.out.bam)

    // ── Reference data (auto-download once if not provided) ───────────────────
    if (params.reference) {
        ch_reference = Channel.value(file(params.reference, checkIfExists: true))
        ch_ref_index = Channel.value(
            ["${params.reference}.amb", "${params.reference}.ann",
             "${params.reference}.bwt", "${params.reference}.pac",
             "${params.reference}.sa",  "${params.reference}.fai"
            ].collect { file(it) })
    } else {
        def dl_ref   = DOWNLOAD_REFERENCE()
        ch_reference = dl_ref.fasta
        ch_ref_index = dl_ref.index
    }

    ch_hostdir = params.hostdir
        ? Channel.value(file(params.hostdir, checkIfExists: true))
        : DOWNLOAD_HOST_INDEX().dir

    ch_kraken_db = ('kraken' in classifiers)
        ? (params.kraken_index
            ? Channel.value(file(params.kraken_index, checkIfExists: true))
            : DOWNLOAD_KRAKEN_DB().dir)
        : Channel.value([])

    // ── Filtering subworkflow ─────────────────────────────────────────────────
    FILTER(ch_inputs, ch_hostdir, ch_reference, ch_ref_index)

    // ── Classification subworkflow ────────────────────────────────────────────
    CLASSIFY(FILTER.out.filtered, classifiers, ch_kraken_db)

    // ── Summarize filtering + classification ───────────────────────────────────
    SUMMARIZE(
        FILTER.out.flagstat
            .join(CLASSIFY.out.kraken_reports)
            .join(CLASSIFY.out.metaphlan_reports)
            .join(CLASSIFY.out.sylph_reports)
    )

    // ── Assembly pipeline (optional, enabled with --assembly) ──────────────────
    if (params.assembly) {
        ASSEMBLE(FILTER.out.unaligned.join(FILTER.out.decoys))

        BINQC(ASSEMBLE.out.dir)
        BINCLASSIFY(ASSEMBLE.out.dir)

        SUMMARIZE_ASSEMBLY(
            ASSEMBLE.out.dir
                .join(BINQC.out.complete)
                .join(BINCLASSIFY.out.complete)
        )
    }
}
