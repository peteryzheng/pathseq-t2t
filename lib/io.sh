#!/usr/bin/env bash

# Shared command execution and BAM validation helpers.
# Validate a BAM by sleeping briefly (to allow EOF flush), then quickcheck and a full read.
# Usage: bam_check_or_die <bam_path> [context_label]
bam_check_or_die() {
  local bam="$1"
  local label="${2:-}"
  [[ -f "$bam" ]] || die "Expected BAM missing: $bam${label:+ ($label)}"

  # Give the filesystem a moment to flush BGZF EOF blocks on network/distributed FS.
  sleep 1

  if ! samtools quickcheck "$bam" >/dev/null 2>&1; then
    die "samtools quickcheck failed: $bam${label:+ ($label)}"
  fi
  # Full read to catch hidden I/O issues (suppress output)
  # if ! samtools view -c "$bam" >/dev/null 2>&1; then
  #   die "Failed to fully read BAM (samtools view -c): $bam${label:+ ($label)}"
  # fi
  log "BAM OK: $bam${label:+ ($label)}"
}


ubam_check_or_die() {
  local bam="$1"
  local label="${2:-}"
  [[ -f "$bam" ]] || die "Expected BAM missing: $bam${label:+ ($label)}"

  sleep 1
  if ! samtools quickcheck -u "$bam" >/dev/null 2>&1; then
    die "samtools quickcheck -u failed: $bam${label:+ ($label)}"
  fi
  # if ! samtools view -c "$bam" >/dev/null 2>&1; then
  #   die "Failed to fully read BAM (samtools view -c): $bam${label:+ ($label)}"
  # fi
  log "BAM OK: $bam${label:+ ($label)}"
}

# Log the exact command (with variables expanded) before executing it.
log_cmd() {
  local rc
  { printf '[CMD] '; printf '%q ' "$@"; printf '\n'; } >&2
  "$@"; rc=$?
  return "$rc"
}
