cmd_prefilter() {
  local decoys_bed=""
  local unaligned_out="" decoys_out="" flagstat_out=""
  local sample_id=""
  local threads=1
  local dont_overwrite=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --input-bam)          input_bam="${2:-}"; shift 2 ;;
      --aligner)            aligner="${2:-}"; shift 2 ;;
      --decoys-to-mask)     decoys_to_mask="${2:-}"; shift 2 ;;
      --sample-id)           sample_id="${2:-}";       shift 2 ;;
      --outdir)              OUTDIR="${2:?--outdir requires a directory path}" ; shift 2 ; _set_outdirs ;;
      --unaligned-out)      unaligned_out="${2:-}"; shift 2 ;;
      --decoys-out)       decoys_out="${2:-}"; shift 2 ;;
      --flagstat-out)       flagstat_out="${2:-}"; shift 2 ;;
      --threads)             threads="${2:-}";         shift 2 ;;
      --dont-overwrite)      dont_overwrite=1;         shift 1 ;;
      -h|--help)
        cat <<'HLP'
Usage: pathseq-t2t prefilter \
  --input-bam <bam> \               Host-aligned bam file to filter
  --aligner [dragen|bwa] \          Aligner used to generate the bam file
  --decoys-to-mask [<bed>|"None"]   BED of decoy/blacklist regions to mask (e.g. viral sequences) \
  [--sample-id <string>]            Sample ID to use for default output naming \
  [--outdir <dir>]                  Output directory (default: ./pst2t_out) \
  [--unaligned-out <bam>]           Output BAM for reads not aligned to the human reference \
  [--decoys-out <bam>]              Output BAM for reads overlapping decoy regions \
  [--flagstat-out <tsv>]            Output TSV for samtools flagstat summary of input \
  [--threads <int>]                 Number of threads to use (default: auto) \
  [--dont-overwrite]                If all outputs already exist and are valid, exit 0

Notes:
  - If --sample-id is provided, default outputs are inferred under <outdir>.
  - If --sample-id is omitted, --unaligned-out, --decoys-out, and --flagstat-out are required.
HLP
        return 0 ;;
      --) shift; break ;;
      -*) die "Unknown option for prefilter: $1" ;;
      *)  die "Unexpected argument to prefilter: $1" ;;
    esac
  done

  require_nonempty "${input_bam}" "--input-bam"
  require_nonempty "${aligner}" "--aligner"
  require_nonempty "${decoys_to_mask}" "--decoys-to-mask"
  require_file "${input_bam}"
  _require_samtools_116

  bam_check_or_die "$input_bam" || die "prefilter: input BAM failed checks: $input_bam"

  # Threads
  if [[ -z "${threads}" ]]; then
    if command -v nproc >/dev/null 2>&1; then
      threads="$(nproc)"
    elif [[ "$OSTYPE" == "darwin"* ]] && command -v sysctl >/dev/null 2>&1; then
      threads="$(sysctl -n hw.ncpu)"
    else
      threads="8"
    fi
  fi
  
  # Normalize/interpret regions; build L_ARG as an array to avoid leading-space issues
  local -a L_ARG=()
  if [[ "${decoys_to_mask,,}" == "none" ]]; then
    decoys_to_mask=""
    L_ARG=()  # no -L used
  else
    require_file "${decoys_to_mask}"
    if command -v readlink >/dev/null 2>&1; then
      local abs_rl; abs_rl="$(readlink -f "${decoys_to_mask}" 2>/dev/null || true)"
      [[ -n "$abs_rl" ]] && decoys_to_mask="$abs_rl"
    fi
    L_ARG=(-L "${decoys_to_mask}")
    # preflight: ensure -L works with this BAM
    # if ! samtools view -@ 1 -b "${input_bam}" "${L_ARG[@]}" -o /dev/null 2>/dev/null; then
    #   die "Preflight failed: samtools could not use -L '${decoys_to_mask}' with ${input_bam}"
    # fi
    # warn (don’t exit) if any BED chrom is missing from BAM header
    miss=$(
      comm -23 \
        <(awk 'NF&&$1!~/^#/{print $1}' "$decoys_to_mask" | sort -u) \
        <(samtools view -H "$input_bam" | awk -F'\t' '$1=="@SQ"{for(i=1;i<=NF;i++) if($i~/^SN:/){print substr($i,4)}}' | sort -u)
    )
    [[ -z "$miss" ]] || echo "[prefilter] WARNING: BED chrom(s) not in BAM header: $miss" >&2
  fi

  # Ensure OUTDIR subfolders are defined even if user didn't pass --outdir explicitly
  if declare -F _set_outdirs >/dev/null; then
    _set_outdirs
  else
    OUTDIR_BAMS="${OUTDIR}/bams"
    OUTDIR_FILTER="${OUTDIR}/filter_stats"
  fi

  mkdir -p "${OUTDIR_FILTER}" "${OUTDIR_BAMS}"

  # Output naming policy:
  # - with --sample-id: fill missing outputs with defaults
  # - without --sample-id: all outputs must be explicitly provided
  if [[ -n "${sample_id}" ]]; then
    [[ -n "${unaligned_out}" ]] || unaligned_out="${OUTDIR_BAMS}/${sample_id}.prefilter.unaligned.bam"
    [[ -n "${decoys_out}"   ]] || decoys_out="${OUTDIR_BAMS}/${sample_id}.prefilter.decoys.bam"
    [[ -n "${flagstat_out}" ]] || flagstat_out="${OUTDIR_FILTER}/${sample_id}.flagstat.tsv"
  else
    require_nonempty "${unaligned_out}" "--unaligned-out (required when --sample-id is not provided)"
    require_nonempty "${decoys_out}" "--decoys-out (required when --sample-id is not provided)"
    require_nonempty "${flagstat_out}" "--flagstat-out (required when --sample-id is not provided)"
  fi

  ensure_parent_dir "${unaligned_out}"
  ensure_parent_dir "${decoys_out}"
  ensure_parent_dir "${flagstat_out}"

  # --dont-overwrite: if all outputs already present & valid, skip work
  if (( dont_overwrite )); then
    local ok_u=0 ok_d=0 ok_f=0
    [[ -s "${unaligned_out}" ]] && samtools quickcheck "${unaligned_out}" >/dev/null 2>&1 && ok_u=1
    [[ -s "${decoys_out}"   ]] && samtools quickcheck "${decoys_out}"   >/dev/null 2>&1 && ok_d=1
    [[ -s "${flagstat_out}" ]] && ok_f=1
    if (( ok_u && ok_d && ok_f )); then
      log "prefilter --dont-overwrite: outputs already present and valid → skipping"
      return 0
    fi
    # if partially present, clear so the step can cleanly re-run
    if (( ok_u==0 || ok_d==0 || ok_f==0 )); then
      log "prefilter --dont-overwrite: partial/invalid outputs detected → cleaning"
      rm -f "${unaligned_out}" "${decoys_out}" "${flagstat_out}" 2>/dev/null || true
    fi
  fi

  log "prefilter aligner=${aligner} threads=${threads}"
  log "  input_bam:   ${input_bam}"
  log "  outputs:     unaligned_seqs=${unaligned_out} decoy_seqs=${decoys_out}"
  log "  flagstat:    ${flagstat_out}"
  log "  decoys_to_mask: ${decoys_to_mask:-<None>}"

  # Single-pass pipeline with tee: flagstat -> unaligned/excluded splits
  case "${aligner}" in
    dragen|DRAGEN)
      time samtools view -@ "${threads}" -b "${input_bam}" \
        | tee >(samtools flagstat --output-fmt tsv -@ "${threads}" - > "${flagstat_out}") \
        | samtools view -@ "${threads}" -bh - -f 3 \
            -U >(samtools view -@ "${threads}" -bh -F 2048 -x SA -x OQ -x MD -o "${unaligned_out}") \
            -o >(samtools view -@ "${threads}" -bh -F 2048 -x SA -x OQ -x MD \
                 "${L_ARG[@]}" -o "${decoys_out}")
      ;;
    bwa|BWA)
      time samtools view -@ "${threads}" -b "${input_bam}" \
        | tee >(samtools flagstat --output-fmt tsv -@ "${threads}" - > "${flagstat_out}") \
        | samtools view -@ "${threads}" -bh - -f 3 -e '[AS]>35' \
            -U >(samtools view -@ "${threads}" -bh -F 2048 -x SA -x OQ -x MD -o "${unaligned_out}") \
            -o >(samtools view -@ "${threads}" -bh -F 2048 -x SA -x OQ -x MD \
                 "${L_ARG[@]}" -o "${decoys_out}")
      ;;
    *) die "Invalid --aligner '${aligner}'. Use 'dragen' or 'bwa'." ;;
  esac

  log "Done."

  # Post-write validations (helper sleeps 1s before quickcheck)
  bam_check_or_die "${unaligned_out}" "prefilter: unaligned_out"
  bam_check_or_die "${decoys_out}"  "prefilter: decoys_out"
  [[ -s "${flagstat_out}" ]] || die "Flagstat TSV is empty: ${flagstat_out}"

  log "prefilter done → unaligned: ${unaligned_out}, decoys: ${decoys_out}, flagstat: ${flagstat_out}"
}
