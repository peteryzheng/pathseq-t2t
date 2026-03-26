cmd_binqc() {
  local sample_id=""
  local assembly_dir="" bins_dir="" qc_dir=""
  local threads="" dont_overwrite=0
  local model="both"
  local checkv_db="${CHECKVDB:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sample-id)              sample_id="${2:-}"; shift 2 ;;
      --outdir)                 OUTDIR="${2:?--outdir requires a directory path}"; shift 2; _set_outdirs ;;
      --assembly-dir)           assembly_dir="${2:-}"; shift 2 ;;
      --bins-dir)               bins_dir="${2:-}"; shift 2 ;;
      --qc-dir)                 qc_dir="${2:-}"; shift 2 ;;
      --threads)                threads="${2:-}"; shift 2 ;;
      --model)                  model="${2:-}"; shift 2 ;;
      --checkv-db)              checkv_db="${2:-}"; shift 2 ;;
      --dont-overwrite)         dont_overwrite=1; shift ;;
      -h|--help)
        cat <<'HLP'
Usage: pathseq-t2t binqc \
  [--sample-id <id>] \
  [--outdir <dir>] \
  [--assembly-dir <dir>] \
  [--bins-dir <dir>] \
  [--qc-dir <dir>] \
  [--model <both|checkm2|checkv>] \
  [--checkv-db <dir>] \
  [--threads <int>] \
  [--dont-overwrite]

What it does:
  (1) Runs bin QC on metabat bin FASTAs
  (2) Default mode runs CheckM2 and CheckV

Notes:
  - If --sample-id is provided, defaults are inferred under <outdir>/assembly/<sample-id>/...
  - If --sample-id is omitted, --bins-dir is required.
  - --model both writes into <assembly_dir>/checkm2 and <assembly_dir>/checkv (default)
  - --model checkm2 writes into <assembly_dir>/checkm2
  - --model checkv writes into <assembly_dir>/checkv
  - --qc-dir is only valid with --model checkm2 or --model checkv
  - For CheckV, provide --checkv-db <dir> or set $CHECKVDB.
HLP
        return 0 ;;
      --) shift; break ;;
      -*) die "Unknown option for binqc: $1" ;;
      *)  die "Unexpected argument to binqc: $1" ;;
    esac
  done

  case "${model}" in
    both|checkm2|checkv) ;;
    *) die "Invalid --model '${model}'. Use both, checkm2, or checkv." ;;
  esac
  if [[ "${model}" == "both" || "${model}" == "checkm2" ]]; then
    _require_checkm2
  fi
  if [[ "${model}" == "both" || "${model}" == "checkv" ]]; then
    _require_checkv
    [[ -n "${checkv_db}" ]] || die "CheckV database not set. Use --checkv-db <dir> or set \$CHECKVDB."
    [[ -d "${checkv_db}" ]] || die "CheckV database directory not found: ${checkv_db}"
  fi

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
    if [[ "${model}" == "both" ]]; then
      [[ -z "${qc_dir}" ]] || die "--qc-dir cannot be used with --model both."
    else
      [[ -n "${qc_dir}" ]] || qc_dir="${assembly_dir}/${model}"
    fi
  else
    require_nonempty "${bins_dir}" "--bins-dir (required when --sample-id is not provided)"
    if [[ "${model}" != "both" ]]; then
      require_nonempty "${qc_dir}" "--qc-dir (required when --sample-id is not provided and --model is not both)"
    else
      require_nonempty "${assembly_dir}" "--assembly-dir (required with --model both when --sample-id is not provided)"
      [[ -z "${qc_dir}" ]] || die "--qc-dir cannot be used with --model both."
    fi
  fi

  [[ -d "${bins_dir}" ]] || die "Bins directory not found: ${bins_dir}"
  if ! compgen -G "${bins_dir}/*.fa" >/dev/null; then
    log "binqc: no bin FASTA files in ${bins_dir} -> nothing to QC"
    return 0
  fi
  local -a bin_fastas=("${bins_dir}"/*.fa)
  local bin_count="${#bin_fastas[@]}"

  local qc_dir_checkm2="" qc_dir_checkv=""
  if [[ "${model}" == "both" ]]; then
    qc_dir_checkm2="${assembly_dir}/checkm2"
    qc_dir_checkv="${assembly_dir}/checkv"
  elif [[ "${model}" == "checkm2" ]]; then
    qc_dir_checkm2="${qc_dir}"
  else
    qc_dir_checkv="${qc_dir}"
  fi
  [[ -n "${qc_dir_checkm2}" ]] && mkdir -p "${qc_dir_checkm2}"
  [[ -n "${qc_dir_checkv}" ]] && mkdir -p "${qc_dir_checkv}"

  if [[ -n "${qc_dir_checkm2}" ]]; then
    local checkm2_report="${qc_dir_checkm2}/quality_report.tsv"
    local checkm2_log="${qc_dir_checkm2}/checkm2.log"
    local summary_tsv="${qc_dir_checkm2}/checkm2_summary.tsv"
    if (( dont_overwrite )) && [[ -s "${checkm2_report}" ]]; then
      log "binqc --dont-overwrite: found ${checkm2_report} -> skipping CheckM2 run"
    elif (( dont_overwrite )) && [[ -s "${summary_tsv}" && -s "${checkm2_log}" ]] \
      && grep -Fq "No DIAMOND annotation was generated. Exiting" "${checkm2_log}"; then
      log "binqc --dont-overwrite: found prior CheckM2 no-DIAMOND outcome -> skipping CheckM2 run"
    else
      log "binqc: CheckM2"
      : > "${checkm2_log}"
      local checkm2_rc=0
      if {
        printf '[CMD] '
        printf '%q ' checkm2 predict \
          --threads "${threads}" \
          --input "${bins_dir}" \
          --output-directory "${qc_dir_checkm2}" \
          -x fa \
          --force \
          --lowmem
        printf '\n'
        checkm2 predict \
          --threads "${threads}" \
          --input "${bins_dir}" \
          --output-directory "${qc_dir_checkm2}" \
          -x fa \
          --force \
          --lowmem
      } > >(tee -a "${checkm2_log}") 2> >(tee -a "${checkm2_log}" >&2); then
        checkm2_rc=0
      else
        checkm2_rc=$?
      fi

      if (( checkm2_rc != 0 )) && ! grep -Fq "No DIAMOND annotation was generated. Exiting" "${checkm2_log}"; then
        die "CheckM2 failed; see log: ${checkm2_log}"
      fi
    fi
    if [[ -s "${checkm2_report}" ]]; then
      # Summarize bin quality classes from CheckM2 quality_report.tsv.
      awk -F'\t' '
        NR==1{
          for (i=1; i<=NF; i++) h[$i]=i
          if (!h["Completeness"] || !h["Contamination"]) {
            print "CheckM2 quality_report.tsv missing Completeness and/or Contamination columns" > "/dev/stderr"
            exit 2
          }
          next
        }
        {
          c = $h["Completeness"] + 0
          x = $h["Contamination"] + 0
          if (x > 10)              fq++
          else if (c > 90 && x < 5)  hq++
          else if (c >= 50 && x < 10) mq++
          else if (c < 50 && x < 10)  lq++
        }
        END{
          printf "HQ\tMQ\tLQ\tND\tFQ\n%d\t%d\t%d\t%d\t%d\n", hq+0, mq+0, lq+0, 0, fq+0
        }
      ' "${checkm2_report}" > "${summary_tsv}" || die "Failed to write CheckM2 summary: ${summary_tsv}"
    elif [[ -s "${checkm2_log}" ]] && grep -Fq "No DIAMOND annotation was generated. Exiting" "${checkm2_log}"; then
      log "binqc: CheckM2 produced no DIAMOND annotations; recording ND=${bin_count} and continuing"
      printf "HQ\tMQ\tLQ\tND\tFQ\n0\t0\t0\t%s\t0\n" "${bin_count}" > "${summary_tsv}" \
        || die "Failed to write CheckM2 summary: ${summary_tsv}"
    else
      die "CheckM2 quality_report.tsv missing: ${checkm2_report}"
    fi
    [[ -s "${summary_tsv}" ]] || die "CheckM2 summary missing: ${summary_tsv}"
  fi

  if [[ -n "${qc_dir_checkv}" ]]; then
    local checkv_summary="${qc_dir_checkv}/quality_summary.tsv"
    if (( dont_overwrite )) && [[ -s "${checkv_summary}" ]]; then
      log "binqc --dont-overwrite: found ${checkv_summary} -> skipping CheckV run"
    else
      # CheckV end_to_end takes one input FASTA; concatenate bin FASTAs.
      local checkv_input="${qc_dir_checkv}/checkv_input_bins.fa"
      cat "${bin_fastas[@]}" > "${checkv_input}"
      [[ -s "${checkv_input}" ]] || die "Failed to create CheckV input FASTA: ${checkv_input}"

      log "binqc: CheckV"
      log_cmd checkv end_to_end \
        "${checkv_input}" \
        "${qc_dir_checkv}" \
        -d "${checkv_db}" \
        -t "${threads}"
      rm -f "${checkv_input}" 2>/dev/null || true
    fi
    [[ -s "${checkv_summary}" ]] || die "CheckV quality_summary.tsv missing: ${checkv_summary}"

    # Summarize CheckV quality classes + provirus counts.
    local checkv_summary_tsv="${qc_dir_checkv}/checkv_summary.tsv"
    awk -F'\t' '
      NR==1{
        for (i=1; i<=NF; i++) h[$i]=i
        if (!h["checkv_quality"] || !h["contamination"] || !h["provirus"]) {
          print "CheckV quality_summary.tsv missing checkv_quality, contamination, and/or provirus columns" > "/dev/stderr"
          exit 2
        }
        next
      }
      {
        q = $h["checkv_quality"]
        c = $h["contamination"]
        p = $h["provirus"]

        if (tolower(p) == "yes") pv++

        # Failed quality (FQ) overrides quality tier assignment.
        if (c != "NA" && c+0 > 10) {
          fq++
          next
        }

        if (q == "High-quality" || q == "Complete")      hq++
        else if (q == "Medium-quality")                   mq++
        else if (q == "Low-quality")                      lq++
        else if (q == "Not-determined" || q == "NA" || q == "") nd++
        else                                              nd++
      }
      END{
        printf "HQ\tMQ\tLQ\tND\tPV\tFQ\n%d\t%d\t%d\t%d\t%d\t%d\n", hq+0, mq+0, lq+0, nd+0, pv+0, fq+0
      }
    ' "${checkv_summary}" > "${checkv_summary_tsv}" || die "Failed to write CheckV summary: ${checkv_summary_tsv}"
    [[ -s "${checkv_summary_tsv}" ]] || die "CheckV summary missing: ${checkv_summary_tsv}"
  fi

  if [[ "${model}" == "both" ]]; then
    log "binqc done -> ${qc_dir_checkm2} and ${qc_dir_checkv}"
  elif [[ -n "${qc_dir_checkm2}" ]]; then
    log "binqc done -> ${qc_dir_checkm2}"
  else
    log "binqc done -> ${qc_dir_checkv}"
  fi
}
