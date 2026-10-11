#!/bin/bash

# delight_qr <text> [out.png]: ANSI QR on stdout, or a PNG when a path is given.
delight_qr() {
  local text="$1" out="${2:-}"
  delight_has_cmd qrencode || delight_die "qrencode is not installed"
  if [[ -n $out ]]; then
    delight_run qrencode -s 8 -m 2 -o "$out" -- "$text"
  else
    qrencode -t ANSIUTF8 -m 2 -- "$text"
  fi
}
