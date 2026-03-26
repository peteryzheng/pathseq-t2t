cmd_binclassify() {
  local sample_id=""
  local assembly_dir="" bins_dir="" classify_dir=""
  local threads="" dont_overwrite=0 keep_intermediate=0
  local extension="fa"
  local gtdbtk_args=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sample-id)            sample_id="${2:-}"; shift 2 ;;
      --outdir)               OUTDIR="${2:?--outdir requires a directory path}"; shift 2; _set_outdirs ;;
      --assembly-dir)         assembly_dir="${2:-}"; shift 2 ;;
      --bins-dir)             bins_dir="${2:-}"; shift 2 ;;
      --classify-dir)         classify_dir="${2:-}"; shift 2 ;;
      --threads)              threads="${2:-}"; shift 2 ;;
      --extension)            extension="${2:-}"; shift 2 ;;
      --gtdbtk-args)          gtdbtk_args="${2:-}"; shift 2 ;;
      --dont-overwrite)       dont_overwrite=1; shift ;;
      --keep-intermediate)    keep_intermediate=1; shift ;;
      -h|--help)
        cat <<'HLP'
Usage: pathseq-t2t binclassify \
  [--sample-id <id>] \
  [--outdir <dir>] \
  [--assembly-dir <dir>] \
  [--bins-dir <dir>] \
  [--classify-dir <dir>] \
  [--threads <int>] \
  [--extension <ext>] \
  [--gtdbtk-args "<args>"] \
  [--dont-overwrite] \
  [--keep-intermediate]

What it does:
  Runs GTDB-Tk classify_wf on metabat bin FASTAs.

Notes:
  - If --sample-id is provided, defaults are inferred under <outdir>/assembly/<sample-id>/...
  - If --sample-id is omitted, --bins-dir is required.
  - Default output is <assembly_dir>/gtdbtk_output.
  - GTDB-Tk requires GTDBTK_DATA_PATH to be set to the reference data directory.
  - GTDB-Tk writes one or more summary files such as gtdbtk.bac120.summary.tsv and/or gtdbtk.ar53.summary.tsv.
HLP
        return 0 ;;
      --) shift; break ;;
      -*) die "Unknown option for binclassify: $1" ;;
      *)  die "Unexpected argument to binclassify: $1" ;;
    esac
  done

  _require_gtdbtk
  local -a gtdbtk_args_ary=()
  _split_cli_args "${gtdbtk_args}" gtdbtk_args_ary

  if [[ -z "${threads}" ]]; then
    if command -v nproc >/dev/null 2>&1; then
      threads="$(nproc)"
    elif [[ "$OSTYPE" == "darwin"* ]] && command -v sysctl >/dev/null 2>&1; then
      threads="$(sysctl -n hw.ncpu)"
    else
      threads="8"
    fi
  fi

  local base=""
  if [[ -n "${sample_id}" ]]; then
    base="${sample_id}"
    [[ -n "${assembly_dir}" ]] || assembly_dir="${OUTDIR%/}/assembly/${base}"
    [[ -n "${bins_dir}" ]] || bins_dir="${assembly_dir}/metabat2_bins"
    [[ -n "${classify_dir}" ]] || classify_dir="${assembly_dir}/gtdbtk_output"
  else
    require_nonempty "${bins_dir}" "--bins-dir (required when --sample-id is not provided)"
    if [[ -z "${classify_dir}" ]]; then
      [[ -n "${assembly_dir}" ]] || die "--classify-dir is required when --sample-id and --assembly-dir are not provided."
      classify_dir="${assembly_dir%/}/gtdbtk_output"
    fi
  fi

  [[ -d "${bins_dir}" ]] || die "Bins directory not found: ${bins_dir}"
  if ! compgen -G "${bins_dir}/*.${extension}" >/dev/null; then
    log "binclassify: no bin FASTA files in ${bins_dir} -> nothing to classify"
    return 0
  fi
  mkdir -p "${classify_dir}"

  if (( dont_overwrite )) && compgen -G "${classify_dir}/*.summary.tsv" >/dev/null; then
    log "binclassify --dont-overwrite: found existing GTDB-Tk summary outputs -> skipping GTDB-Tk run"
  else
    # Wipe stale partial output from a prior failed run to prevent GTDB-Tk resume errors
    if [[ -d "${classify_dir}" ]]; then
      rm -rf "${classify_dir}"
      mkdir -p "${classify_dir}"
    fi
    log "binclassify: GTDB-Tk classify_wf"
    log_cmd gtdbtk classify_wf \
      --genome_dir "${bins_dir}" \
      --out_dir "${classify_dir}" \
      --extension "${extension}" \
      --cpus "${threads}" \
      "${gtdbtk_args_ary[@]}"
  fi

  compgen -G "${classify_dir}/*.summary.tsv" >/dev/null || die "GTDB-Tk summary outputs missing in: ${classify_dir}"

  # Summarize classified vs non-classified bins across all GTDB-Tk summary files.
  local gtdbtk_summary_tsv="${classify_dir}/gtdbtk_summary.tsv"
  awk -F'\t' '
    FNR==1{
      for (i=1; i<=NF; i++) h[$i]=i
      if (!h["classification"]) {
        print "GTDB-Tk summary missing classification column: " FILENAME > "/dev/stderr"
        exit 2
      }
      next
    }
    {
      v = $h["classification"]
      if (v == "" || v == "Unclassified") nc++
      else c++
    }
    END{
      printf "C\tNC\n%d\t%d\n", c+0, nc+0
    }
  ' "${classify_dir}"/*.summary.tsv > "${gtdbtk_summary_tsv}" || die "Failed to write GTDB-Tk summary: ${gtdbtk_summary_tsv}"
  [[ -s "${gtdbtk_summary_tsv}" ]] || die "GTDB-Tk summary missing: ${gtdbtk_summary_tsv}"

  # GTDB-Tk symlinks the summary into the parent dir from classify/.
  # Promote to a real file so it survives cleanup and rsync correctly.
  for lnk in "${classify_dir}"/gtdbtk.*.summary.tsv; do
    [[ -L "${lnk}" ]] || continue
    local real
    real="$(readlink -f "${lnk}")"
    rm -f "${lnk}"
    cp -p "${real}" "${lnk}"
  done

  # Cleanup GTDB-Tk intermediates.
  if (( ! keep_intermediate )); then
    rm -rf "${classify_dir}/identify" "${classify_dir}/align" "${classify_dir}/classify" 2>/dev/null || true
  fi

  log "binclassify done -> ${classify_dir}"
}
