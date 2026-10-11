#!/bin/bash

# Marked blocks in user-owned files (hyprland.lua, omarchy-menu.jsonc).
# The first insertion snapshots the original file; removal restores that
# snapshot byte-for-byte when nothing else changed, and otherwise strips only
# the lines between the markers.

DELIGHT_BLOCK_BEGIN=">>> omarchy-delight >>>"
DELIGHT_BLOCK_END="<<< omarchy-delight <<<"
DELIGHT_BACKUP_DIR="$DELIGHT_STATE_DIR/core/backups"

delight_block_backup_path() {
  printf '%s/%s\n' "$DELIGHT_BACKUP_DIR" "$(printf '%s' "$1" | sed 's|/|%|g')"
}

# Print <file> without any Delight block. Missing files print nothing.
delight_block_strip() {
  local file="$1"
  [[ -f $file ]] || return 0
  awk -v b="$DELIGHT_BLOCK_BEGIN" -v e="$DELIGHT_BLOCK_END" '
    index($0, b) { skip = 1; next }
    skip && index($0, e) { skip = 0; next }
    !skip { print }
  ' "$file"
}

delight_block_present() {
  [[ -f $1 ]] && grep -qF -- "$DELIGHT_BLOCK_BEGIN" "$1"
}

delight_block_snapshot() {
  local file="$1" backup
  backup=$(delight_block_backup_path "$file")
  [[ -e $backup || -e $backup.absent ]] && return 0
  if [[ -f $file ]]; then
    delight_write "$backup" <"$file"
  else
    : | delight_write "$backup.absent"
  fi
}

# delight_block_set_end <file> <comment-prefix> <body>: append (or replace) the block at the end.
delight_block_set_end() {
  local file="$1" prefix="$2" body="$3" base
  delight_block_snapshot "$file"
  base=$(delight_block_strip "$file")
  {
    [[ -n $base ]] && printf '%s\n\n' "$base"
    printf '%s %s\n%s\n%s %s\n' "$prefix" "$DELIGHT_BLOCK_BEGIN" "$body" "$prefix" "$DELIGHT_BLOCK_END"
  } | delight_write "$file"
}

# delight_block_set_jsonc <file> <body>: place the block inside the top-level object,
# just before its closing brace. Body entries must each end with a comma.
delight_block_set_jsonc() {
  local file="$1" body="$2" base
  delight_block_snapshot "$file"
  base=$(delight_block_strip "$file")
  [[ -n $(tr -d '[:space:]' <<<"$base") ]] || base=$'{\n}'
  awk -v b="// $DELIGHT_BLOCK_BEGIN" -v e="// $DELIGHT_BLOCK_END" -v body="$body" '
    { lines[NR] = $0 }
    END {
      for (i = NR; i > 0; i--) if (lines[i] ~ /^[[:space:]]*}[[:space:]]*$/) { close_at = i; break }
      if (!close_at) close_at = NR + 1
      prev = 0
      for (i = close_at - 1; i > 0; i--) if (lines[i] !~ /^[[:space:]]*(\/\/.*)?$/) { prev = i; break }
      for (i = 1; i < close_at; i++) {
        line = lines[i]
        if (i == prev && line !~ /[,{][[:space:]]*$/) line = line ","
        print line
      }
      print "  " b
      print body
      print "  " e
      for (i = close_at; i <= NR; i++) print lines[i]
      if (close_at > NR) print "}"
    }
  ' <<<"$base" | delight_write "$file"
}

# Remove the block, restoring the snapshot when the stripped file still matches it.
delight_block_remove() {
  local file="$1" backup stripped
  backup=$(delight_block_backup_path "$file")
  if [[ -f $backup.absent ]]; then
    if [[ -f $file ]]; then
      stripped=$(delight_block_strip "$file")
      if [[ -z $(tr -d '[:space:]{}' <<<"$stripped") ]]; then
        delight_rm "$file"
      else
        printf '%s\n' "$stripped" | delight_write "$file"
      fi
    fi
    delight_rm "$backup.absent"
    return 0
  fi
  if [[ -f $backup ]]; then
    if [[ -f $file ]] && delight_block_matches_backup "$file" "$backup"; then
      delight_write "$file" "$(stat -c '%a' -- "$file")" <"$backup"
    elif delight_block_present "$file"; then
      delight_warn "$file changed since install; removing only the Delight block"
      delight_block_strip_in_place "$file"
    fi
    delight_rm "$backup"
    return 0
  fi
  delight_block_present "$file" && delight_block_strip_in_place "$file"
  return 0
}

delight_block_strip_in_place() {
  delight_block_strip "$1" | delight_write "$1" "$(stat -c '%a' -- "$1")"
}

# True when the file minus our block is the snapshot, ignoring the comma and
# blank lines we may have added.
delight_block_matches_backup() {
  local file="$1" backup="$2" normalize='{ sub(/,[ \t]*$/, "") } !/^[ \t]*$/ { print }'
  cmp -s <(delight_block_strip "$file" | awk "$normalize") <(awk "$normalize" "$backup")
}
