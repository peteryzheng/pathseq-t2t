require_file()  { [ -f "$1" ] || die "Required file not found: $1"; }
require_nonempty() { [ -n "$1" ] || die "Missing required value: $2"; }
ensure_parent_dir() {
  # ensure parent directory exists for output files
  local p; p="$(dirname -- "$1")"
  [ -d "$p" ] || mkdir -p "$p"
}

# Parse a CLI args string into an array variable name.
# Preserves quoted groups, e.g. --foo "a b" -> ["--foo","a b"].
# Rejects shell control/operator characters to avoid command injection.
_split_cli_args() { # usage: _split_cli_args "<raw args>" <out_array_var>
  local raw="${1:-}"
  local outvar="${2:-}"
  local -a parsed=()
  local tok q serialized=""

  [[ -n "${outvar}" ]] || die "_split_cli_args: missing output array variable name."
  if [[ -z "${raw}" ]]; then
    eval "${outvar}=()"
    return 0
  fi

  if [[ "${raw}" == *$'\n'* || "${raw}" == *$'\r'* || "${raw}" == *';'* || \
        "${raw}" == *'&'* || "${raw}" == *'|'* || "${raw}" == *'<'* || \
        "${raw}" == *'>'* || "${raw}" == *'`'* || "${raw}" == *'$('* ]]; then
    die "Unsafe characters in argument string: ${raw}"
  fi

  # Disable glob expansion while tokenizing.
  set -f
  if ! eval "set -- ${raw}"; then
    set +f
    die "Could not parse argument string: ${raw}"
  fi
  set +f
  parsed=("$@")

  for tok in "${parsed[@]}"; do
    printf -v q '%q' "${tok}"
    serialized+="${serialized:+ }${q}"
  done
  eval "${outvar}=(${serialized})"
}
