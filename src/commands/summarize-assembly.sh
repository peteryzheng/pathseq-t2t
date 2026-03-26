cmd_summarize_assembly() {
  local sample_id=""
  local assembly_dir=""
  local outdir_results=""
  local input_flagstat=""
  local verbose_flag=

  : "${OUTDIR:=./pst2t_out}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sample-id)        sample_id="${2:-}"; shift 2 ;;
      --outdir)           OUTDIR="${2:?--outdir requires a directory path}"; shift 2; _set_outdirs ;;
      --assembly-dir)     assembly_dir="${2:-}"; shift 2 ;;
      --results-dir)      outdir_results="${2:-}"; shift 2 ;;
      --input-flagstat)   input_flagstat="${2:-}"; shift 2 ;;
      -v|--verbose)       verbose_flag="--verbose"; shift ;;
      -h|--help)
        cat <<'HLP'
Usage: pathseq-t2t summarize-assembly \
  --sample-id <id> \
  [--outdir <dir>] \
  [--assembly-dir <dir>] \
  [--results-dir <dir>] \
  [--input-flagstat <tsv>] \
  [-v|--verbose]

Description:
  Summarize assembly QC metrics and per-bin classification for a single sample.

Outputs (to --results-dir):
  - <sample>.assembly_summary.tsv   (one-row pipeline QC summary)
  - <sample>.bin_summary.tsv        (one row per bin: checkm2/checkv/gtdbtk)
HLP
        return 0 ;;
      --) shift; break ;;
      *) die "Unknown summarize-assembly option: $1" ;;
    esac
  done

  [[ -z "${sample_id}" ]] && die "[summarize-assembly] --sample-id is required."

  if [[ -z "${outdir_results}" ]]; then
    outdir_results="${OUTDIR%/}/results"
  fi
  mkdir -p "${outdir_results}"

  log "summarize-assembly: sample=${sample_id} OUTDIR=${OUTDIR} results_dir=${outdir_results}"

  if command -v python3 >/dev/null 2>&1; then
    local args=( "${SCRIPT_DIR%/src}/scripts/pst2t_summarize_assembly.py"
       --sample-id "${sample_id}"
       --results-dir "${outdir_results}" )

    [[ -n ${OUTDIR:-} ]]          && args+=( --outdir "${OUTDIR}" )
    [[ -n ${assembly_dir:-} ]]    && args+=( --assembly-dir "${assembly_dir}" )
    [[ -n ${input_flagstat:-} ]]  && args+=( --input-flagstat "${input_flagstat}" )
    [[ -n ${verbose_flag:-} ]]    && args+=( -v )

    log_cmd python3 "${args[@]}"
  else
    die "python3 not found on PATH."
  fi

  log "summarize-assembly done → results: ${outdir_results}"
}
