cmd_summarize() {
  local sample_id=""
  local outdir_results=""         # defaulted after parsing from OUTDIR
  local verbose_flag=

  # explicit file-level inputs (optional overrides)
  local input_flagstat=""
  local qcfilter_metrics_unaligned=""
  local qcfilter_metrics_decoys=""
  local flagstat_paired_aln=""
  local t2tfilter_flagstat_paired=""
  local flagstat_unpaired_aln=""
  local t2tfilter_flagstat_unpaired=""
  local kraken_report_paired=""
  local kraken_report_unpaired=""
  local metaphlan_report=""
  local sylph_report_paired=""
  local sylph_report_unpaired=""

  # OUTDIR defaults up front; user may override via --outdir
  : "${OUTDIR:=./pst2t_out}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sample-id)                 sample_id="${2:-}"; shift 2 ;;
      --outdir)                    OUTDIR="${2:?--outdir requires a directory path}"; shift 2; _set_outdirs ;;
      --results-dir)               outdir_results="${2:-}"; shift 2 ;;

      # explicit file inputs (instead of dir inference)
      --input-flagstat)               input_flagstat="${2:-}"; shift 2 ;;
      --qcfilter-metrics-unaligned)      qcfilter_metrics_unaligned="${2:-}"; shift 2 ;;
      --qcfilter-metrics-decoys)         qcfilter_metrics_decoys="${2:-}"; shift 2 ;;
      # --t2tfilter-flagstat-paired)              flagstat_paired_aln="${2:-}"; shift 2 ;;
      --t2tfilter-flagstat-paired)            t2tfilter_flagstat_paired="${2:-}"; shift 2 ;;
      # --flagstat-unpaired-aln)            flagstat_unpaired_aln="${2:-}"; shift 2 ;;
      --t2tfilter-flagstat-unpaired)          t2tfilter_flagstat_unpaired="${2:-}"; shift 2 ;;
      --kraken-report-paired)             kraken_report_paired="${2:-}"; shift 2 ;;
      --kraken-report-unpaired)           kraken_report_unpaired="${2:-}"; shift 2 ;;
      --metaphlan-report)                 metaphlan_report="${2:-}"; shift 2 ;;
      --sylph-report-paired)              sylph_report_paired="${2:-}"; shift 2 ;;
      --sylph-report-unpaired)            sylph_report_unpaired="${2:-}"; shift 2 ;;

      -v|--verbose)                verbose_flag="--verbose"; shift ;;
      -h|--help)
        cat <<'HLP'
Usage: pathseq-t2t summarize [ARGS] \

Core options:
  --sample-id <id>                 (required)
  [--outdir <dir>]                 Root directory for inference (default: ./pst2t_out)
  [--results-dir <dir>]            Where to write final outputs (default: <outdir>/results)
  [-v|--verbose]                   Verbose summarizer logs

Explicit file inputs (optional — use to bypass dir inference):
  --input-flagstat <tsv>               e.g., <ID>.flagstat.tsv
  --qcfilter-metrics-unaligned <txt>      e.g., <ID>.prefilter.unaligned.filter_metrics.txt
  --qcfilter-metrics-decoys <txt>         e.g., <ID>.prefilter.decoys.filter_metrics.txt
  --t2tfilter-flagstat-paired <tsv>            e.g., <ID>.qcfilt_paired.t2t_unaln.flagstat.tsv
  --t2tfilter-flagstat-unpaired <tsv>          e.g., <ID>.qcfilt_unpaired.t2t_unaln.flagstat.tsv
  --kraken-report-paired <txt>             e.g., <ID>.paired.kraken.report.txt
  --kraken-report-unpaired <txt>           e.g., <ID>.unpaired.kraken.report.txt
  --metaphlan-report <txt>                 e.g., <ID>.metaphlan.report.txt
  --sylph-report-paired <txt>              e.g., <ID>.paired.sylph.report.txt
  --sylph-report-unpaired <txt>            e.g., <ID>.unpaired.sylph.report.txt

Description:
  Combine filtering + classification summaries and write normalized Kraken2 / MetaPhlAn / Sylph tables.
  If explicit files are not provided, inputs are inferred from --outdir.

Outputs (to --results-dir):
  - <sample>.summary.tsv
  - <sample>.kraken.txt        (if Kraken2 present)
  - <sample>.metaphlan.txt     (if MetaPhlAn present)
  - <sample>.sylph.txt         (if Sylph present)
HLP
        return 0 ;;
      --) shift; break ;;
      *) die "Unknown summarize option: $1" ;;
    esac
  done

  [[ -z "${sample_id}" ]] && die "[summarize] --sample-id is required."

  # Default results dir if not provided
  if [[ -z "${outdir_results}" ]]; then
    outdir_results="${OUTDIR%/}/results"
  fi
  mkdir -p "${outdir_results}"

  # Sanity log
  log "summarize: sample=${sample_id} OUTDIR=${OUTDIR} results_dir=${outdir_results}"

  if command -v python3 >/dev/null 2>&1; then
    args=( "${SCRIPT_DIR%/src}/scripts/pst2t_summarize.py"
       --sample-id "${sample_id}"
       --results-dir "${outdir_results}" )

    [[ -n ${OUTDIR:-} ]]                        && args+=( --outdir "${OUTDIR}" )
    [[ -n ${input_flagstat:-} ]]            && args+=( --input-flagstat "${input_flagstat}" )
    [[ -n ${qcfilter_metrics_unaligned:-} ]]   && args+=( --qcfilter-metrics-unaligned "${qcfilter_metrics_unaligned}" )
    [[ -n ${qcfilter_metrics_decoys:-} ]]      && args+=( --qcfilter-metrics-decoys "${qcfilter_metrics_decoys}" )
    # [[ -n ${flagstat_paired_aln:-} ]]           && args+=( --flagstat-paired-aln "${flagstat_paired_aln}" )
    [[ -n ${t2tfilter_flagstat_paired:-} ]]         && args+=( --t2tfilter-flagstat-paired "${t2tfilter_flagstat_paired}" )
    # [[ -n ${flagstat_unpaired_aln:-} ]]         && args+=( --flagstat-unpaired-aln "${flagstat_unpaired_aln}" )
    [[ -n ${t2tfilter_flagstat_unpaired:-} ]]       && args+=( --t2tfilter-flagstat-unpaired "${t2tfilter_flagstat_unpaired}" )
    [[ -n ${kraken_report_paired:-} ]]          && args+=( --kraken-report-paired "${kraken_report_paired}" )
    [[ -n ${kraken_report_unpaired:-} ]]        && args+=( --kraken-report-unpaired "${kraken_report_unpaired}" )
    [[ -n ${metaphlan_report:-} ]]              && args+=( --metaphlan-report "${metaphlan_report}" )
    [[ -n ${sylph_report_paired:-} ]]         && args+=( --sylph-report-paired "${sylph_report_paired}" )
    [[ -n ${sylph_report_unpaired:-} ]]       && args+=( --sylph-report-unpaired "${sylph_report_unpaired}" )
    [[ -n ${verbose_flag:-} ]]                  && args+=( -v )

    # Real run
    log_cmd python3 "${args[@]}"
  else
    die "python3 not found on PATH."
  fi

  log "summarize done → results: ${outdir_results}"
}
