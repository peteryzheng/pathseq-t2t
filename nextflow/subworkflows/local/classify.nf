include { CLASSIFY_KRAKEN    } from '../../modules/classify'
include { CLASSIFY_METAPHLAN } from '../../modules/classify'
include { CLASSIFY_SYLPH     } from '../../modules/classify'

workflow CLASSIFY {
    take:
    ch_filtered      // channel: [meta, paired_bam, unpaired_bam]
    classifiers      // list<string>
    ch_kraken_db     // channel: path (or [])
    ch_metaphlan_db  // channel: path (bowtie2 dir, or [])
    ch_sylph_db      // channel: path (.syldb file, or [])

    main:
    // Placeholder channels emit empty lists so SUMMARIZE joins always resolve.
    ch_kraken_reports    = ch_filtered.map { meta, _p, _u -> [meta, []] }
    ch_metaphlan_reports = ch_filtered.map { meta, _p, _u -> [meta, []] }
    ch_sylph_reports     = ch_filtered.map { meta, _p, _u -> [meta, []] }

    if ('kraken' in classifiers) {
        CLASSIFY_KRAKEN(ch_filtered, ch_kraken_db)
        ch_kraken_reports = CLASSIFY_KRAKEN.out.report_paired
            .join(CLASSIFY_KRAKEN.out.report_unpaired)
            .map { meta, rp, ru -> [meta, [rp, ru]] }
    }

    if ('metaphlan' in classifiers) {
        CLASSIFY_METAPHLAN(ch_filtered, ch_metaphlan_db)
        ch_metaphlan_reports = CLASSIFY_METAPHLAN.out.report
            .map { meta, r -> [meta, [r]] }
    }

    if ('sylph' in classifiers) {
        CLASSIFY_SYLPH(ch_filtered, ch_sylph_db)
        ch_sylph_reports = CLASSIFY_SYLPH.out.report_paired
            .join(CLASSIFY_SYLPH.out.report_unpaired)
            .map { meta, rp, ru -> [meta, [rp, ru]] }
    }

    emit:
    kraken_reports    = ch_kraken_reports
    metaphlan_reports = ch_metaphlan_reports
    sylph_reports     = ch_sylph_reports
}
