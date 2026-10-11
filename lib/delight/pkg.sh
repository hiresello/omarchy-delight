#!/bin/bash

# Packages. Only packages Delight actually added are recorded, so uninstall
# never removes something the user already had.

delight_pkg_present() {
  pacman -Q -- "$1" >/dev/null 2>&1
}

# delight_pkg_add <id> <repo|aur> <packages...>
delight_pkg_add() {
  local id="$1" source="$2" pkg
  shift 2
  [[ $source == "repo" || $source == "aur" ]] || delight_die "pkg source must be repo or aur, got '$source'"
  for pkg in "$@"; do
    if delight_pkg_present "$pkg"; then
      delight_log "$id: package $pkg already installed"
      continue
    fi
    if [[ $source == "repo" ]]; then
      if delight_has_cmd omarchy-pkg-add; then
        delight_run omarchy-pkg-add "$pkg" || delight_die "$id: could not install $pkg"
      else
        delight_run sudo pacman -S --noconfirm --needed -- "$pkg" || delight_die "$id: could not install $pkg"
      fi
    else
      if delight_has_cmd omarchy-pkg-aur-add; then
        delight_run omarchy-pkg-aur-add "$pkg" || delight_die "$id: could not install $pkg from the AUR"
      else
        delight_run yay -S --noconfirm --needed -- "$pkg" || delight_die "$id: could not install $pkg from the AUR"
      fi
    fi
    delight_state_add "$id" packages "$(jq -cn --arg n "$pkg" --arg s "$source" '{name:$n,source:$s}')"
  done
}

# Remove the packages <id> recorded, skipping any another Delight module also recorded.
delight_pkg_remove() {
  local id="$1" entry name owners remove=()
  while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    name=$(jq -r '.name' <<<"$entry")
    owners=$(delight_state_owners packages ".name == \"$name\"" | grep -vx -- "$id" || true)
    if [[ -n $owners ]]; then
      delight_log "$id: keeping $name (also used by: ${owners//$'\n'/ })"
    elif delight_pkg_present "$name"; then
      remove+=("$name")
    fi
    delight_state_del "$id" packages "$entry"
  done < <(delight_state_list "$id" packages)
  if ((${#remove[@]} > 0)); then
    delight_run sudo pacman -Rns --noconfirm -- "${remove[@]}" || delight_warn "$id: could not remove ${remove[*]}"
  fi
}
