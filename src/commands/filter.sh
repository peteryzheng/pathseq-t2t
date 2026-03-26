cmd_filter() {
  local input_bam="" aligner="" decoys_to_mask=""
  local sample_id="" outdir="" hostdir="" reference=""
  local threads="" dont_overwrite=0 keep_intermediate=0
  local prefilter_args="" qcfilter_args="" t2tfilter_args=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --input-bam)         input_bam="${2:-}"; shift 2 ;;
      --aligner)           aligner="${2:-}"; shift 2 ;;
      --decoys-to-mask)    decoys_to_mask="${2:-}"; shift 2 ;;
      --sample-id)         sample_id="${2:-}"; shift 2 ;;
      --outdir)            outdir="${2:-}"; shift 2 ;;
      --hostdir)           hostdir="${2:-}"; shift 2 ;;
      --reference)         reference="${2:-}"; shift 2 ;;
      --threads)           threads="${2:-}"; shift 2 ;;
      --dont-overwrite)    dont_overwrite=1; shift ;;
      --keep-intermediate) keep_intermediate=1; shift ;;
      --prefilter-args)    prefilter_args="${2:-}"; shift 2 ;;
      --qcfilter-args)     qcfilter_args="${2:-}"; shift 2 ;;
      --t2tfilter-args)    t2tfilter_args="${2:-}"; shift 2 ;;
      -h|--help)
        cat <<'HLP'
Usage: pathseq-t2t filter \
  --input-bam <bam> \
  --aligner <dragen|bwa> \
  --decoys-to-mask <bed|None> \
  [--sample-id <id>] \
  [--outdir <dir>] \
  [--hostdir <dir>] \
  [--reference <t2t.fa>] \
  [--threads <int>] \
  [--dont-overwrite] \
  [--keep-intermediate] \
  [--prefilter-args "<args>"] \
  [--qcfilter-args "<args>"] \
  [--t2tfilter-args "<args>"]

Description:
  Wrapper that runs:
    1) prefilter
    2) qcfilter
    3) t2tfilter

Required:
  - --input-bam, --aligner, --decoys-to-mask
  - --hostdir <dir> or $HOSTDIR
  - --reference <t2t.fa> or $T2TREF

Notes:
  - With --sample-id, intermediate handoff paths are deterministic under <outdir>/bams.
  - Without --sample-id, this wrapper requires explicit --outdir and derives a run-specific base
    from --input-bam filename.
HLP
        return 0 ;;
      --) shift; break ;;
      -*) die "Unknown option for filter: $1" ;;
      *)  die "Unexpected argument to filter: $1" ;;
    esac
  done

  require_nonempty "${input_bam}" "--input-bam"
  require_nonempty "${aligner}" "--aligner"
  require_nonempty "${decoys_to_mask}" "--decoys-to-mask"
  require_file "${input_bam}"

  # Apply outdir override once for this wrapper execution.
  if [[ -n "${outdir}" ]]; then
    OUTDIR="${outdir}"
    _set_outdirs
  fi
  mkdir -p "${OUTDIR_BAMS}" "${OUTDIR_FILTER}"

  local run_base=""
  if [[ -n "${sample_id}" ]]; then
    run_base="${sample_id}"
  else
    run_base="$(basename "${input_bam%.bam}")"
  fi

  local pre_u="${OUTDIR_BAMS}/${run_base}.prefilter.unaligned.bam"
  local pre_d="${OUTDIR_BAMS}/${run_base}.prefilter.decoys.bam"
  local pre_f="${OUTDIR_FILTER}/${run_base}.flagstat.tsv"
  local qc_p="${OUTDIR_BAMS}/${run_base}.qcfilt_paired.bam"
  local qc_u="${OUTDIR_BAMS}/${run_base}.qcfilt_unpaired.bam"
  local qc_mu="${OUTDIR_FILTER}/${run_base}.prefilter.unaligned.filter_metrics.txt"
  local qc_md="${OUTDIR_FILTER}/${run_base}.prefilter.decoys.filter_metrics.txt"
  local t2t_p="${OUTDIR_BAMS}/${run_base}.t2tfilt_paired.bam"
  local t2t_u="${OUTDIR_BAMS}/${run_base}.t2tfilt_unpaired.bam"
  local t2t_fp_unaln="${OUTDIR_FILTER}/${run_base}.qcfilt_paired.t2t_unaln.flagstat.tsv"
  local t2t_fu_unaln="${OUTDIR_FILTER}/${run_base}.qcfilt_unpaired.t2t_unaln.flagstat.tsv"

  local -a pf_extra=() qf_extra=() tf_extra=()
  _split_cli_args "${prefilter_args}" pf_extra
  _split_cli_args "${qcfilter_args}" qf_extra
  _split_cli_args "${t2tfilter_args}" tf_extra

  local -a pf_cmd=(
    --input-bam "${input_bam}"
    --aligner "${aligner}"
    --decoys-to-mask "${decoys_to_mask}"
    --unaligned-out "${pre_u}"
    --decoys-out "${pre_d}"
    --flagstat-out "${pre_f}"
  )
  [[ -n "${sample_id}" ]] && pf_cmd+=( --sample-id "${sample_id}" )
  [[ -n "${outdir}"    ]] && pf_cmd+=( --outdir "${outdir}" )
  [[ -n "${threads}"   ]] && pf_cmd+=( --threads "${threads}" )
  (( dont_overwrite ))    && pf_cmd+=( --dont-overwrite )
  pf_cmd+=( "${pf_extra[@]}" )

  local -a qf_cmd=(
    --input-unaligned "${pre_u}"
    --input-decoys "${pre_d}"
    --paired-out "${qc_p}"
    --unpaired-out "${qc_u}"
    --metrics-unaligned "${qc_mu}"
    --metrics-decoys "${qc_md}"
  )
  [[ -n "${sample_id}" ]] && qf_cmd+=( --sample-id "${sample_id}" )
  [[ -n "${outdir}"    ]] && qf_cmd+=( --outdir "${outdir}" )
  [[ -n "${hostdir}"   ]] && qf_cmd+=( --hostdir "${hostdir}" )
  [[ -n "${threads}"   ]] && qf_cmd+=( --threads "${threads}" )
  (( dont_overwrite ))    && qf_cmd+=( --dont-overwrite )
  (( keep_intermediate )) && qf_cmd+=( --keep-intermediate )
  qf_cmd+=( "${qf_extra[@]}" )

  local -a tf_cmd=(
    --input-paired "${qc_p}"
    --input-unpaired "${qc_u}"
    --output-paired "${t2t_p}"
    --output-unpaired "${t2t_u}"
    --flagstat-unaln-paired "${t2t_fp_unaln}"
    --flagstat-unaln-unpaired "${t2t_fu_unaln}"
    --decoys-to-mask "${decoys_to_mask}"
  )
  [[ -n "${sample_id}"  ]] && tf_cmd+=( --sample-id "${sample_id}" )
  [[ -n "${outdir}"     ]] && tf_cmd+=( --outdir "${outdir}" )
  [[ -n "${reference}"  ]] && tf_cmd+=( --reference "${reference}" )
  [[ -n "${threads}"    ]] && tf_cmd+=( --threads "${threads}" )
  (( dont_overwrite ))     && tf_cmd+=( --dont-overwrite )
  (( keep_intermediate ))  && tf_cmd+=( --keep-intermediate )
  tf_cmd+=( "${tf_extra[@]}" )

  log "filter: running prefilter -> qcfilter -> t2tfilter"
  cmd_prefilter "${pf_cmd[@]}"
  cmd_qcfilter "${qf_cmd[@]}"
  cmd_t2tfilter "${tf_cmd[@]}"
  log "filter done"
}
