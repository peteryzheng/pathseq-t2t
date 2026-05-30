include { PREFILTER } from '../../modules/prefilter'
include { QCFILTER  } from '../../modules/qcfilter'
include { T2TFILTER } from '../../modules/t2tfilter'

workflow FILTER {
    take:
    ch_inputs      // channel: [meta, bam]
    ch_hostdir     // channel: path
    ch_reference   // channel: path
    ch_ref_index   // channel: list<path>
    ch_decoys_bed  // channel: path (or NO_FILE sentinel)

    main:
    PREFILTER(ch_inputs, ch_decoys_bed)

    QCFILTER(
        PREFILTER.out.unaligned.join(PREFILTER.out.decoys),
        ch_hostdir
    )

    T2TFILTER(
        QCFILTER.out.paired.join(QCFILTER.out.unpaired),
        ch_reference,
        ch_ref_index
    )

    emit:
    filtered  = T2TFILTER.out.paired.join(T2TFILTER.out.unpaired)
    flagstat  = PREFILTER.out.flagstat
        .join(QCFILTER.out.metrics_unaligned)
        .join(QCFILTER.out.metrics_decoys)
        .join(T2TFILTER.out.flagstat_paired)
        .join(T2TFILTER.out.flagstat_unpaired)
    unaligned = PREFILTER.out.unaligned
    decoys    = PREFILTER.out.decoys
}
