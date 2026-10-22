#!/usr/bin/env bash

# Shared command execution and BAM validation helpers.
# Validate a BAM: wait until it exists and passes quickcheck (up to 60 s, to allow EOF flush).
# Usage: bam_check_or_die <bam_path> [context_label]
bam_check_or_die() {
  local bam="$1"
  local label="${2:-}"

  # Outputs written through >(...) process substitutions are not waited on by bash, so the
  # writer may still be finishing (or flushing BGZF EOF blocks on a network FS): poll up to 60 s.
  local i
  for (( i = 0; i < 60; i++ )); do
    sleep 1
    [[ -f "$bam" ]] && samtools quickcheck "$bam" >/dev/null 2>&1 && break
  done
  [[ -f "$bam" ]] || die "Expected BAM missing: $bam${label:+ ($label)}"
  (( i < 60 )) || die "samtools quickcheck failed: $bam${label:+ ($label)}"
  # Full read to catch hidden I/O issues (suppress output)
  # if ! samtools view -c "$bam" >/dev/null 2>&1; then
  #   die "Failed to fully read BAM (samtools view -c): $bam${label:+ ($label)}"
  # fi
  log "BAM OK: $bam${label:+ ($label)}"
}


ubam_check_or_die() {
  local bam="$1"
  local label="${2:-}"
  # Same polling as bam_check_or_die
  local i
  for (( i = 0; i < 60; i++ )); do
    sleep 1
    [[ -f "$bam" ]] && samtools quickcheck -u "$bam" >/dev/null 2>&1 && break
  done
  [[ -f "$bam" ]] || die "Expected BAM missing: $bam${label:+ ($label)}"
  (( i < 60 )) || die "samtools quickcheck -u failed: $bam${label:+ ($label)}"
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
