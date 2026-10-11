#!/bin/bash

# Side-effect wrappers. With DELIGHT_DRY_RUN=1 each one prints "DRY: <action>"
# instead of acting. Reads are never wrapped.

delight_dry_print() {
  local out="DRY:" arg
  for arg in "$@"; do
    out+=" $(printf '%q' "$arg")"
  done
  printf '%s\n' "$out"
}

# Run a command, or print it in dry-run mode.
delight_run() {
  if delight_dry; then
    delight_dry_print "$@"
  else
    "$@"
  fi
}

# Same, but discard the command's stdout.
delight_run_quiet() {
  if delight_dry; then
    delight_dry_print "$@"
  else
    "$@" >/dev/null
  fi
}

delight_mkdir() {
  [[ -d $1 ]] && return 0
  delight_run mkdir -p -- "$1"
}

delight_rm() {
  [[ -e $1 || -L $1 ]] || return 0
  delight_run rm -rf -- "$1"
}

# Remove a directory only if it is empty.
delight_rmdir_empty() {
  [[ -d $1 ]] || return 0
  [[ -z $(ls -A -- "$1") ]] || return 0
  delight_run rmdir -- "$1"
}

delight_symlink() {
  local target="$1" link="$2"
  if [[ -L $link && $(readlink -- "$link") == "$target" ]]; then
    return 0
  fi
  delight_mkdir "$(dirname -- "$link")"
  delight_run ln -sfn -- "$target" "$link"
}

# Write stdin to a file atomically. No-op when the content is unchanged.
delight_write() {
  local dest="$1" mode="${2:-}" tmp
  tmp=$(mktemp)
  cat >"$tmp"
  if [[ -f $dest ]] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    return 0
  fi
  if delight_dry; then
    rm -f "$tmp"
    delight_dry_print write "$dest"
    return 0
  fi
  mkdir -p -- "$(dirname -- "$dest")"
  [[ -n $mode ]] && chmod "$mode" "$tmp"
  [[ -z $mode ]] && chmod 644 "$tmp"
  mv -f -- "$tmp" "$dest"
}

delight_copy() {
  local src="$1" dest="$2" mode
  mode=$(stat -c '%a' -- "$src")
  delight_write "$dest" "$mode" <"$src"
}
