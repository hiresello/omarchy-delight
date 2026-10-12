#!/bin/bash
# Research spike: build a vCard 3.0 as a NameDrop-style fallback and
# optionally render it as a QR code.
# Standalone spike only; not wired into install; does not source lib/ or
# reference modules/.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: vcard-qr.sh --name "Full Name" [options]

Build a vCard 3.0 (CRLF line endings) for a NameDrop-style QR fallback.

Options:
  --name "Full Name"   required; N is derived by splitting on the last space
  --tel NUMBER         optional, emitted as TEL;TYPE=CELL
  --email ADDR         optional, emitted as EMAIL;TYPE=INTERNET
  --org ORG            optional
  --url URL            optional
  --out FILE           .vcf writes the vCard, .png renders a QR via qrencode
  --help               this text
  --self-test          run built-in checks, print TAP

With no --out the vCard is printed to stdout; if qrencode is installed and
stdout is a TTY an ANSI QR is printed too.
EOF
}

# Escape a vCard text value per RFC 2426: backslash, comma, semicolon, newline.
esc() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//,/\\,}
  s=${s//;/\\;}
  s=${s//$'\n'/\\n}
  printf '%s' "$s"
}

build_vcard() {
  local name=$1 tel=$2 email=$3 org=$4 url=$5
  local last first
  if [[ $name == *" "* ]]; then
    last=${name##* }
    first=${name% *}
  else
    last=$name
    first=
  fi
  printf 'BEGIN:VCARD\r\n'
  printf 'VERSION:3.0\r\n'
  printf 'N:%s;%s;;;\r\n' "$(esc "$last")" "$(esc "$first")"
  printf 'FN:%s\r\n' "$(esc "$name")"
  if [[ -n $org ]]; then
    printf 'ORG:%s\r\n' "$(esc "$org")"
  fi
  if [[ -n $tel ]]; then
    printf 'TEL;TYPE=CELL:%s\r\n' "$(esc "$tel")"
  fi
  if [[ -n $email ]]; then
    printf 'EMAIL;TYPE=INTERNET:%s\r\n' "$(esc "$email")"
  fi
  if [[ -n $url ]]; then
    printf 'URL:%s\r\n' "$(esc "$url")"
  fi
  printf 'END:VCARD\r\n'
}

self_test() {
  local fails=0 out rc=0

  echo '1..5'
  "$0" --tel +1 >/dev/null 2>&1 || rc=$?
  if ((rc != 0)); then
    echo 'ok 1 - missing --name is an error'
  else
    echo 'not ok 1 - missing --name is an error'
    fails=1
  fi

  out=$(build_vcard 'Doe, Jr.; "x"' '' '' '' '')
  if [[ $out == *'FN:Doe\, Jr.\; "x"'* ]]; then
    echo 'ok 2 - comma and semicolon escaped in FN'
  else
    echo 'not ok 2 - comma and semicolon escaped in FN'
    fails=1
  fi

  out=$(build_vcard 'Ada Lovelace' '' '' '' '')
  if [[ $out == *'N:Lovelace;Ada;;;'* ]]; then
    echo 'ok 3 - N derived by splitting on last space'
  else
    echo 'not ok 3 - N derived by splitting on last space'
    fails=1
  fi

  out=$(build_vcard 'Madonna' '' '' '' '')
  if [[ $out == *'N:Madonna;;;;'* ]]; then
    echo 'ok 4 - single-word name yields N:Madonna;;;;'
  else
    echo 'not ok 4 - single-word name yields N:Madonna;;;;'
    fails=1
  fi

  if [[ $out == *$'\r\n'* ]]; then
    echo 'ok 5 - output uses CRLF line endings'
  else
    echo 'not ok 5 - output uses CRLF line endings'
    fails=1
  fi

  exit "$fails"
}

name=
tel=
email=
org=
url=
out=
while (($#)); do
  case $1 in
    --name)
      name=${2:?--name needs a value}
      shift 2
      ;;
    --tel)
      tel=${2:?--tel needs a value}
      shift 2
      ;;
    --email)
      email=${2:?--email needs a value}
      shift 2
      ;;
    --org)
      org=${2:?--org needs a value}
      shift 2
      ;;
    --url)
      url=${2:?--url needs a value}
      shift 2
      ;;
    --out)
      out=${2:?--out needs a value}
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    --self-test)
      self_test
      ;;
    *)
      echo "vcard-qr: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z $name ]]; then
  echo 'vcard-qr: --name is required' >&2
  exit 2
fi

vcard=$(build_vcard "$name" "$tel" "$email" "$org" "$url")
case $out in
  '')
    printf '%s' "$vcard"
    if [[ -t 1 ]] && command -v qrencode >/dev/null 2>&1; then
      printf '%s' "$vcard" | qrencode -t ansiutf8
    fi
    ;;
  *.png)
    if ! command -v qrencode >/dev/null 2>&1; then
      echo 'vcard-qr: install qrencode (pacman -S qrencode)' >&2
      exit 3
    fi
    printf '%s' "$vcard" | qrencode -o "$out"
    ;;
  *.vcf)
    printf '%s' "$vcard" >"$out"
    ;;
  *)
    echo "vcard-qr: --out must end in .png or .vcf: $out" >&2
    exit 2
    ;;
esac
