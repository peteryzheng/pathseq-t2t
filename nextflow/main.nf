nextflow.enable.dsl = 2

include { DOWNLOAD_HG38      } from './modules/cram_to_bam'
include { CRAM_TO_BAM        } from './modules/cram_to_bam'
include { PREFILTER          } from './modules/prefilter'
include { QCFILTER           } from './modules/qcfilter'
include { T2TFILTER          } from './modules/t2tfilter'
include { CLASSIFY_KRAKEN    } from './modules/classify'
include { CLASSIFY_METAPHLAN } from './modules/classify'
include { CLASSIFY_SYLPH     } from './modules/classify'
include { ASSEMBLE           } from './modules/assemble'
include { BINQC              } from './modules/binqc'
include { BINCLASSIFY        } from './modules/binclassify'
include { SUMMARIZE          } from './modules/summarize'
include { SUMMARIZE_ASSEMBLY } from './modules/summarize_assembly'

workflow {

    // ── Param validation ───────────────────────────────────────────────────────
    if (!params.samplesheet) error "Required: --samplesheet <csv>"
    if (!params.hostdir)     error "Required: --hostdir <dir>"
    if (!params.reference)   error "Required: --reference <t2t.fa>"

    def classifiers = params.classifiers.tokenize(',')*.trim()*.toLowerCase()

    if ('kraken'    in classifiers && !params.kraken_index)    error "'kraken' in --classifiers but --kraken_index not set"
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
            tuple(row.sample_id, file(row.bam, checkIfExists: true))
        }

    // ── CRAM → BAM conversion (auto-detected by extension) ────────────────────
    ch_samples.branch {
        cram: it[1].name.endsWith('.cram')
        bam:  true
    }.set { ch_by_type }

    ch_hg38_ref = params.hg38_ref
        ? Channel.value(file(params.hg38_ref, checkIfExists: true))
        : DOWNLOAD_HG38(ch_by_type.cram.first().map { "fetch" }).ref

    CRAM_TO_BAM(ch_by_type.cram, ch_hg38_ref)
    ch_inputs = ch_by_type.bam.mix(CRAM_TO_BAM.out.bam)

    // ── Filtering pipeline ─────────────────────────────────────────────────────
    PREFILTER(ch_inputs)

    QCFILTER(
        PREFILTER.out.unaligned.join(PREFILTER.out.decoys)
    )

    T2TFILTER(
        QCFILTER.out.paired.join(QCFILTER.out.unpaired)
    )

    ch_filtered = T2TFILTER.out.paired.join(T2TFILTER.out.unpaired)

    // ── Classification (parallel) ──────────────────────────────────────────────
    // Classifier report channels: emit [sample_id, [file1, file2]] (or [] when not run).
    // Placeholder channels provide empty lists so the SUMMARIZE join always resolves.
    ch_kraken_reports   = ch_samples.map { sid, _ -> [sid, []] }
    ch_metaphlan_reports = ch_samples.map { sid, _ -> [sid, []] }
    ch_sylph_reports    = ch_samples.map { sid, _ -> [sid, []] }

    if ('kraken' in classifiers) {
        CLASSIFY_KRAKEN(ch_filtered)
        ch_kraken_reports = CLASSIFY_KRAKEN.out.report_paired
            .join(CLASSIFY_KRAKEN.out.report_unpaired)
            .map { sid, rp, ru -> [sid, [rp, ru]] }
    }

    if ('metaphlan' in classifiers) {
        CLASSIFY_METAPHLAN(ch_filtered)
        ch_metaphlan_reports = CLASSIFY_METAPHLAN.out.report
            .map { sid, r -> [sid, [r]] }
    }

    if ('sylph' in classifiers) {
        CLASSIFY_SYLPH(ch_filtered)
        ch_sylph_reports = CLASSIFY_SYLPH.out.report_paired
            .join(CLASSIFY_SYLPH.out.report_unpaired)
            .map { sid, rp, ru -> [sid, [rp, ru]] }
    }

    // ── Summarize filtering + classification ───────────────────────────────────
    ch_filter_stats = PREFILTER.out.flagstat
        .join(QCFILTER.out.metrics_unaligned)
        .join(QCFILTER.out.metrics_decoys)
        .join(T2TFILTER.out.flagstat_paired)
        .join(T2TFILTER.out.flagstat_unpaired)

    SUMMARIZE(
        ch_filter_stats
            .join(ch_kraken_reports)
            .join(ch_metaphlan_reports)
            .join(ch_sylph_reports)
    )

    // ── Assembly pipeline (optional, enabled with --assembly) ──────────────────
    if (params.assembly) {
        ASSEMBLE(
            PREFILTER.out.unaligned.join(PREFILTER.out.decoys)
        )

        // BINQC and BINCLASSIFY run in parallel on the assembled bins.
        BINQC(ASSEMBLE.out.dir)
        BINCLASSIFY(ASSEMBLE.out.dir)

        // SUMMARIZE_ASSEMBLY waits for all three assembly steps via explicit join.
        SUMMARIZE_ASSEMBLY(
            ASSEMBLE.out.dir
                .join(BINQC.out.complete)
                .join(BINCLASSIFY.out.complete)
        )
    }
}
