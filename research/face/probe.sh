#!/bin/bash

# delight face probe — read-only inventory for IR face login.
# Collects userspace facts and prints a verdict from the A16 feasibility
# study's decision tree. Does not capture frames, toggle an illuminator,
# or change kernel, PAM, or Howdy state.
#
# Hardware behavior is not claimed here. Verdicts describe these logs only.

set -euo pipefail

export LC_ALL=C

face_probe_usage() {
  cat <<'USAGE'
Usage: delight face probe [--output FILE] [--fixture DIR]

Collect a redacted text report about cameras on this boot and print a
plain-language verdict. Read docs/manual/face-probe.md before acting on it.

  --output FILE    report path (default: ./delight-face-probe.txt)
  --fixture DIR    classify canned command output instead of this machine

The script only reads. It does not install packages, capture frames, or
turn an illuminator on. Missing tools are reported, not installed.
Common Arch packages when you want every section: usbutils, v4l-utils,
libcamera.
USAGE
}

face_probe_die() {
  printf 'delight face probe: error: %s\n' "$1" >&2
  exit "${2:-1}"
}

face_probe_user() {
  if [[ -n ${DELIGHT_FACE_PROBE_USER:-} ]]; then
    printf '%s\n' "$DELIGHT_FACE_PROBE_USER"
  else
    id -un
  fi
}

face_probe_home() {
  printf '%s\n' "${DELIGHT_FACE_PROBE_HOME:-$HOME}"
}

# Username is scrubbed as its own token, except when that token is also a
# hardware word (video, camera, media, …). Home-directory paths are always
# scrubbed. Serial fields, MAC addresses, and disk UUIDs are always scrubbed.
face_probe_redact() {
  local user home escaped sed_args=()
  user=$(face_probe_user)
  home=$(face_probe_home)
  if [[ -n $home && $home != / ]]; then
    escaped=$(printf '%s' "$home" | sed -e 's/[.[\*^$()+?{|\\]/\\&/g')
    sed_args+=(-e "s#${escaped}(/|[[:space:]]|$)#[home]\\1#g")
  fi
  if [[ $user =~ ^[A-Za-z0-9._-]+$ && ${#user} -ge 2 ]]; then
    sed_args+=(-e "s#/(home|Users)/${user}(/|[[:space:]]|$)#/\\1/[user]\\2#g")
    case " $user " in
      *" camera "* | *" video "* | *" media "* | *" linux "* | *" kernel "* | *" asus "* | *" zenbook "* | *" root "* | *" user "* | *" test "* | *" none "* | *" usb "* | *" led "* | *" ir "* | *" cam "* | *" cci "* | *" himax "* | *" dmesg "* | *" serial "* | *" mac "* | *" home "* | *" delight "* | *" omarchy "* | *" arch "*) ;;
      *)
        sed_args+=(-e "s#(^|[^A-Za-z0-9._-])${user}([^A-Za-z0-9._-]|$)#\\1[user]\\2#g")
        ;;
    esac
  fi
  sed -E \
    "${sed_args[@]}" \
    -e 's/\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b/[mac]/g' \
    -e 's/\b([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}\b/[mac]/g' \
    -e 's/\b([0-9A-Fa-f]{4}\.){2}[0-9A-Fa-f]{4}\b/[mac]/g' \
    -e 's/(PARTUUID|UUID)=[^[:space:]]+/\1=[uuid]/g' \
    -e 's/(iSerial[[:space:]]+[0-9]+[[:space:]]+)[^[:space:]]+/\1[serial]/Ig' \
    -e 's/(serial-number[[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1[serial]/Ig' \
    -e 's/(Serial(Number)?[[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1[serial]/Ig' \
    -e 's/((serial|board_serial)no=)[^[:space:]]+/\1[serial]/Ig'
}

face_probe_shopt_nullglob() {
  # shopt -p is non-zero when the option is off, which would trip set -e.
  FACE_PROBE_NULLGLOB_SAVED=$(shopt -p nullglob || true)
  shopt -s nullglob
}

face_probe_shopt_restore() {
  eval "$FACE_PROBE_NULLGLOB_SAVED"
}

face_probe_write_cmd() {
  local dest="$1"
  shift
  local err out rc
  err=$(mktemp)
  set +e
  out=$("$@" 2>"$err")
  rc=$?
  set -e
  if [[ $rc -ne 0 && -z $out ]]; then
    local message
    message=$(head -n 1 -- "$err" | tr -cd '[:print:][:space:]')
    if [[ -z $message ]]; then
      printf '(unreadable: %s failed)\n' "$1" >"$dest"
    else
      printf '(unreadable: %s)\n' "$message" >"$dest"
    fi
  elif [[ -z $out ]]; then
    printf '(no output)\n' >"$dest"
  else
    printf '%s\n' "$out" >"$dest"
  fi
  rm -f -- "$err"
}

face_probe_collect_dt() {
  local proc="$1" model_out="$2" nodes_out="$3"
  local model_file="$proc/device-tree/model" dt="$proc/device-tree"
  if [[ -f $model_file ]]; then
    tr -cd '[:print:][:space:]' <"$model_file" | sed 's/[[:space:]]*$//' >"$model_out"
    printf '\n' >>"$model_out"
  else
    printf '%s\n' "(no /proc/device-tree/model)" >"$model_out"
  fi
  if [[ ! -d $dt ]]; then
    printf '%s\n' "(no device tree)" >"$nodes_out"
    return 0
  fi
  local dir rel compatible blob found=0
  : >"$nodes_out"
  while IFS= read -r dir; do
    rel=${dir#"$dt"/}
    [[ -n $rel && $rel != "$dt" ]] || continue
    case "$rel" in
      *serial* | *chosen* | *firmware* | *aliases*) continue ;;
    esac
    compatible=""
    if [[ -f $dir/compatible ]]; then
      compatible=$(tr '\0' ' ' <"$dir/compatible" | tr -cd '[:print:][:space:]')
    fi
    blob="$rel $compatible"
    if printf '%s\n' "$blob" | grep -Eiq 'camss|csiphy|ov02c10|hm1092|himax|qcom,cci|camcc|camera'; then
      printf '%s compatible=%s\n' "$rel" "${compatible:-"(none)"}" >>"$nodes_out"
      found=1
    fi
  done < <(find "$dt" -type d | sort)
  if [[ $found -eq 0 ]]; then
    printf '%s\n' "(no camera nodes)" >"$nodes_out"
  fi
}

face_probe_collect_uvcvideo() {
  local sys="$1" dest="$2" dir
  dir="$sys/bus/usb/drivers/uvcvideo"
  if [[ ! -d $dir ]]; then
    printf '%s\n' "absent" >"$dest"
    return 0
  fi
  local entry base entries=()
  face_probe_shopt_nullglob
  for entry in "$dir"/*; do
    base=$(basename -- "$entry")
    case "$base" in
      bind | unbind | uevent | module | new_id | remove_id) continue ;;
    esac
    entries+=("$base")
  done
  face_probe_shopt_restore
  {
    printf '%s\n' "present"
    if ((${#entries[@]} > 0)); then
      printf '%s\n' "${entries[@]}" | sort
    fi
  } >"$dest"
}

face_probe_collect_leds() {
  local sys="$1" dest="$2" led base entries=()
  face_probe_shopt_nullglob
  for led in "$sys"/class/leds/*; do
    base=$(basename -- "$led")
    entries+=("$base")
  done
  face_probe_shopt_restore
  if ((${#entries[@]} == 0)); then
    printf '%s\n' "(none)" >"$dest"
  else
    printf '%s\n' "${entries[@]}" | sort >"$dest"
  fi
}

face_probe_collect_media() {
  local devdir="$1" dest="$2"
  if ! command -v media-ctl >/dev/null 2>&1; then
    printf '%s\n' "(not installed: media-ctl; package v4l-utils)" >"$dest"
    return 0
  fi
  local nodes=() node
  face_probe_shopt_nullglob
  nodes=("$devdir"/media*)
  face_probe_shopt_restore
  if ((${#nodes[@]} == 0)); then
    printf '%s\n' "(no /dev/media* nodes)" >"$dest"
    return 0
  fi
  local buf="" node_out err rc ok=0
  err=$(mktemp)
  for node in "${nodes[@]}"; do
    set +e
    node_out=$(media-ctl -d "$node" -p 2>"$err")
    rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then
      ok=1
      buf+="===== media-ctl -d ${node} -p ====="$'\n'"${node_out}"$'\n'
    else
      local message
      message=$(head -n 1 -- "$err" | tr -cd '[:print:][:space:]')
      [[ -n $message ]] || message="media-ctl failed"
      buf+="===== media-ctl -d ${node} -p ====="$'\n'"(unreadable: ${message})"$'\n'
    fi
  done
  rm -f -- "$err"
  if [[ $ok -eq 0 ]]; then
    printf '%s\n' "(unreadable: media-ctl failed)" >"$dest"
  else
    printf '%s\n' "$buf" >"$dest"
  fi
}

face_probe_collect_dmesg() {
  local dest="$1" raw err rc filtered count
  if ! command -v dmesg >/dev/null 2>&1; then
    printf '%s\n' "(not installed: dmesg)" >"$dest"
    return 0
  fi
  err=$(mktemp)
  set +e
  raw=$(dmesg --color=never 2>"$err")
  rc=$?
  if [[ $rc -ne 0 ]]; then
    raw=$(dmesg 2>"$err")
    rc=$?
  fi
  set -e
  if [[ $rc -ne 0 ]]; then
    local message
    message=$(head -n 1 -- "$err" | tr -cd '[:print:][:space:]')
    [[ -n $message ]] || message="dmesg failed"
    printf '(unreadable: %s)\n' "$message" >"$dest"
    rm -f -- "$err"
    return 0
  fi
  rm -f -- "$err"
  filtered=$(printf '%s\n' "$raw" | grep -aEi 'himax|hm1092|ov02c10|camss|cci|pm8010' || true)
  if [[ -z $filtered ]]; then
    printf '%s\n' "(no matching lines)" >"$dest"
    return 0
  fi
  count=$(printf '%s\n' "$filtered" | grep -c . || true)
  if [[ $count -gt 400 ]]; then
    {
      printf '%s\n' "$filtered" | head -n 400
      printf '%s\n' "(truncated to 400 matching lines)"
    } >"$dest"
  else
    printf '%s\n' "$filtered" >"$dest"
  fi
}

face_probe_collect_live() {
  local dest="$1"
  local proc="${DELIGHT_FACE_PROBE_PROC:-/proc}"
  local sys="${DELIGHT_FACE_PROBE_SYS:-/sys}"
  local devdir="${DELIGHT_FACE_PROBE_DEV:-/dev}"

  if command -v uname >/dev/null 2>&1; then
    uname -r >"$dest/uname.txt"
  else
    printf '%s\n' "(not installed: uname)" >"$dest/uname.txt"
  fi
  face_probe_collect_dt "$proc" "$dest/model.txt" "$dest/dt-nodes.txt"
  if [[ -r $proc/cmdline ]]; then
    tr -cd '[:print:][:space:]' <"$proc/cmdline" | sed 's/[[:space:]]*$//' >"$dest/cmdline.txt"
    printf '\n' >>"$dest/cmdline.txt"
  else
    printf '%s\n' "(unreadable: /proc/cmdline)" >"$dest/cmdline.txt"
  fi
  if command -v lsusb >/dev/null 2>&1; then
    face_probe_write_cmd "$dest/lsusb.txt" lsusb
  else
    printf '%s\n' "(not installed: lsusb; package usbutils)" >"$dest/lsusb.txt"
  fi
  face_probe_collect_uvcvideo "$sys" "$dest/uvcvideo.txt"
  if command -v v4l2-ctl >/dev/null 2>&1; then
    face_probe_write_cmd "$dest/v4l2.txt" v4l2-ctl --list-devices
    if grep -q '^(no output)$' "$dest/v4l2.txt"; then
      printf '%s\n' "(no devices)" >"$dest/v4l2.txt"
    fi
  else
    printf '%s\n' "(not installed: v4l2-ctl; package v4l-utils)" >"$dest/v4l2.txt"
  fi
  face_probe_collect_media "$devdir" "$dest/media.txt"
  face_probe_collect_dmesg "$dest/dmesg.txt"
  if command -v cam >/dev/null 2>&1; then
    face_probe_write_cmd "$dest/cam.txt" cam -l
  else
    printf '%s\n' "(not installed: cam; package libcamera)" >"$dest/cam.txt"
  fi
  face_probe_collect_leds "$sys" "$dest/leds.txt"
}

# Print key=value facts. Heuristics are documented in docs/manual/face-probe.md.
# They were checked against synthetic fixtures, not against A16 hardware.
face_probe_classify() {
  local dir="$1"
  awk -v dir="$dir" '
    function slurp(name,    path, line, text) {
      path = dir "/" name
      text = ""
      while ((getline line < path) > 0)
        text = text line "\n"
      close(path)
      return text
    }
    function known_text(text) {
      if (text == "") return 0
      if (text ~ /^\(not installed/) return 0
      if (text ~ /^\(unreadable/) return 0
      return 1
    }
    function is_ir(s,    t) {
      t = tolower(s)
      return (t ~ /infrared/ || t ~ /hm1092/ || t ~ /himax/ || t ~ /ir[-_ ]?cam/ \
        || t ~ /(^|[^a-z0-9])ir([^a-z0-9]|$)/ || t ~ /(^|[^a-z0-9])nir([^a-z0-9]|$)/)
    }
    function is_usb_header(s) {
      return (s ~ /\(usb-/ || tolower(s) ~ /uvcvideo/)
    }
    function yn(flag) {
      return flag ? "yes" : "no"
    }
    function consider_v4l2(header, block) {
      if (is_ir(header) && is_usb_header(header)) uvc_ir = 1
      if (is_ir(header) && !is_usb_header(header)) {
        ir_node = 1
        if (block ~ /\/dev\/video/) ir_stream = 1
      }
      if (tolower(header) ~ /camss/ || header ~ /\(platform/) mipi = 1
      if (tolower(header block) ~ /ov02c10/) {
        mipi = 1
        rgb = 1
      }
    }
    function scan_v4l2(text,    n, lines, i, line) {
      if (!known_text(text)) {
        v4l2_known = 0
        return
      }
      v4l2_known = 1
      header = ""
      block = ""
      n = split(text, lines, "\n")
      for (i = 1; i <= n; i++) {
        line = lines[i]
        if (line == "") {
          if (header != "") consider_v4l2(header, block)
          header = ""
          block = ""
          continue
        }
        if (header == "" && line !~ /^[ \t]/) header = line
        else block = block line "\n"
      }
      if (header != "") consider_v4l2(header, block)
    }
    function uvc_bound(text,    n, lines, i) {
      n = split(text, lines, "\n")
      for (i = 1; i <= n; i++) {
        if (lines[i] ~ /^[0-9]+-[0-9]+(\.[0-9]+)?:[0-9]+\.[0-9]+$/) return 1
      }
      return 0
    }
    function consider_media(block,    low, is_uvc, is_mipi) {
      low = tolower(block)
      is_uvc = (low ~ /driver[ \t]+uvcvideo/ || low ~ /bus info[ \t]+usb/)
      is_mipi = (low ~ /camss/ || low ~ /csiphy/ || low ~ /ov02c10/ \
        || low ~ /qcom[,_-]cci/ || low ~ /bus info[ \t]+platform/)
      if (is_mipi) mipi = 1
      if (low ~ /ov02c10/) rgb = 1
      if (is_uvc && is_ir(block)) uvc_ir = 1
      if (!is_uvc && (low ~ /hm1092/ || low ~ /himax/)) ir_node = 1
    }
    function scan_media(text,    n, lines, i, line, block) {
      if (!known_text(text)) {
        media_known = 0
        return
      }
      media_known = 1
      if (text ~ /^\(no \/dev\/media/) return
      n = split(text, lines, "\n")
      block = ""
      for (i = 1; i <= n; i++) {
        line = lines[i]
        if (line ~ /^===== / && block != "") {
          consider_media(block)
          block = line "\n"
        } else block = block line "\n"
      }
      if (block != "") consider_media(block)
    }
    function scan_cam(text,    n, lines, i, line, cur) {
      if (!known_text(text)) {
        cam_known = 0
        return
      }
      cam_known = 1
      cur = 0
      n = split(text, lines, "\n")
      for (i = 1; i <= n; i++) {
        line = lines[i]
        if (line ~ /^[0-9]+:/) cur = is_ir(line)
        else if (cur && line ~ /[0-9]+x[0-9]+/) ir_stream = 1
      }
    }
    function note_text(text) {
      low = tolower(text)
      if (low ~ /ov02c10/) {
        mipi = 1
        rgb = 1
      }
      if (low ~ /camss/ || low ~ /csiphy/ || low ~ /qcom[,_-]cci/) mipi = 1
      if (low ~ /hm1092/ || low ~ /himax/) ir_node = 1
      if (low ~ /pm8010/) pm8010 = 1
    }
    function scan_blacklist(text,    chunk, rest, n, parts, i, tok) {
      chunk = text
      while (match(chunk, /(module_blacklist|modprobe\.blacklist)=[^[:space:]]+/)) {
        rest = substr(chunk, RSTART, RLENGTH)
        chunk = substr(chunk, RSTART + RLENGTH)
        sub(/^[^=]+=/, "", rest)
        n = split(rest, parts, ",")
        for (i = 1; i <= n; i++) {
          tok = parts[i]
          if (tok ~ /^(i2c_qcom_cci|qcom_camss|ov02c10|hm1092|himax_hm1092|uvcvideo)$/) {
            if (index("," blacklist ",", "," tok ",") == 0) {
              if (blacklist != "") blacklist = blacklist ","
              blacklist = blacklist tok
            }
          }
        }
      }
    }
    BEGIN {
      uvc_ir = mipi = rgb = ir_node = ir_stream = pm8010 = usb_named = 0
      v4l2_known = media_known = cam_known = dmesg_known = lsusb_known = 0
      blacklist = ""
      lsusb = slurp("lsusb.txt")
      uvc = slurp("uvcvideo.txt")
      v4l2 = slurp("v4l2.txt")
      media = slurp("media.txt")
      dmesg = slurp("dmesg.txt")
      cam = slurp("cam.txt")
      dt = slurp("dt-nodes.txt")
      cmdline = slurp("cmdline.txt")
      lsusb_known = known_text(lsusb)
      scan_v4l2(v4l2)
      scan_media(media)
      scan_cam(cam)
      if (known_text(dmesg)) {
        dmesg_known = 1
        note_text(dmesg)
      }
      if (dt != "" && dt !~ /^\(no device tree\)/ && dt !~ /^\(no camera nodes\)/) note_text(dt)
      if (lsusb_known && is_ir(lsusb)) {
        if (uvc_bound(uvc)) uvc_ir = 1
        else usb_named = 1
      }
      scan_blacklist(cmdline)
      if (uvc ~ /^present/) uvcvideo = "present"
      else if (uvc ~ /^absent/) uvcvideo = "absent"
      else uvcvideo = "unknown"
      print "uvc_ir=" yn(uvc_ir)
      print "mipi=" yn(mipi)
      print "rgb=" yn(rgb)
      print "ir_node=" yn(ir_node)
      print "ir_stream=" yn(ir_stream)
      print "pm8010=" yn(pm8010)
      print "usb_named=" yn(usb_named)
      print "v4l2_known=" yn(v4l2_known)
      print "media_known=" yn(media_known)
      print "cam_known=" yn(cam_known)
      print "dmesg_known=" yn(dmesg_known)
      print "lsusb_known=" yn(lsusb_known)
      print "uvcvideo=" uvcvideo
      print "blacklist=" blacklist
    }
  '
}

face_probe_flag() {
  local file="$1" key="$2" line
  line=$(grep -E "^${key}=" "$file" | head -n 1 || true)
  printf '%s\n' "${line#*=}"
}

face_probe_verdict() {
  local flags="$1"
  local uvc_ir mipi rgb ir_node ir_stream usb_named pm8010
  local v4l2_known media_known cam_known dmesg_known lsusb_known blacklist
  uvc_ir=$(face_probe_flag "$flags" uvc_ir)
  mipi=$(face_probe_flag "$flags" mipi)
  rgb=$(face_probe_flag "$flags" rgb)
  ir_node=$(face_probe_flag "$flags" ir_node)
  ir_stream=$(face_probe_flag "$flags" ir_stream)
  usb_named=$(face_probe_flag "$flags" usb_named)
  pm8010=$(face_probe_flag "$flags" pm8010)
  v4l2_known=$(face_probe_flag "$flags" v4l2_known)
  media_known=$(face_probe_flag "$flags" media_known)
  cam_known=$(face_probe_flag "$flags" cam_known)
  dmesg_known=$(face_probe_flag "$flags" dmesg_known)
  lsusb_known=$(face_probe_flag "$flags" lsusb_known)
  blacklist=$(face_probe_flag "$flags" blacklist)

  local id prose extra=""
  if [[ $uvc_ir == yes ]]; then
    id="uvc-ir"
    prose="A USB UVC infrared camera is present. The next path is Howdy Next. linux-enable-ir-emitter applies only when that camera's illuminator is a UVC control. The A16 feasibility study expects the built-in cameras to be MIPI CSI-2, not USB, so confirm this is not an external webcam. This probe did not enroll a face, change PAM, or test an illuminator. Unverified."
    if [[ $mipi == yes ]]; then
      extra=" MIPI camera data was also present and is included in this report. The USB infrared device is what selects the Howdy Next path."
    fi
  elif [[ $ir_node == yes && $ir_stream == yes ]]; then
    id="ir-capture-listed"
    prose="An infrared capture node is listed by libcamera or v4l2. This probe did not read frames and did not check the illuminator, so a usable login camera is unverified. Stay off the Howdy Next path until a dark-room capture shows a face lit by infrared."
  elif [[ $ir_node == yes && $ir_stream == no && $cam_known == yes && $v4l2_known == yes ]]; then
    id="mipi-ir-no-stream"
    prose="An infrared sensor node is present on the MIPI path and no infrared capture stream is available to userspace. That points to an illuminator or driver issue, not a Howdy Next setup. This probe did not capture frames and did not turn an illuminator on or off. Both are unverified."
  elif [[ $ir_node == yes ]]; then
    id="incomplete"
    prose="An infrared node appeared, but libcamera or v4l2 output was missing, so this probe could not see enough to tell a missing stream from a missing tool. Install v4l-utils and libcamera and re-run. Do not treat this as an illuminator result. Unverified."
  elif [[ $usb_named == yes && $mipi == no ]]; then
    id="usb-ir-not-uvc"
    prose="A USB device whose name looks infrared is present, and uvcvideo is not bound to it. That is not the UVC Howdy Next path, and it is not a MIPI camera stack. This probe did not identify the bridge. Unverified."
  elif [[ $mipi == yes ]]; then
    id="mipi-rgb-only"
    if [[ $rgb == yes ]]; then
      prose="MIPI camera data is present, including the OV02C10 RGB sensor, and no IR sensor node (HM1092 or Himax) appeared. Kernel and device-tree work is still needed for the infrared camera. Howdy Next does not apply yet. This probe did not capture frames, so the RGB stream is unverified."
    else
      prose="MIPI camera data is present and no IR sensor node (HM1092 or Himax) appeared. The OV02C10 RGB sensor was not named. Kernel and device-tree work is still needed for the infrared camera. Howdy Next does not apply yet. This probe did not capture frames, so any RGB stream is unverified."
    fi
  elif [[ $dmesg_known != yes || $v4l2_known != yes || $media_known != yes || $lsusb_known != yes ]]; then
    id="incomplete"
    prose="This probe could not see enough to choose a path. A command was missing or the kernel log was unreadable, and no camera stack was proven another way. Install usbutils, v4l-utils, and libcamera, and re-run in a shell that can read dmesg. Do not treat this as proof the camera is missing. Unverified."
  else
    id="nothing"
    prose="No UVC infrared camera and no MIPI camera stack (no CAMSS, OV02C10, or HM1092) showed up in the commands that succeeded. The running kernel or device tree is not exposing the camera stack. That is a packaging or device-tree problem, not proof that the sensors are missing. A blacklisted module or a mainline device tree without camera nodes looks the same. This probe did not capture frames. Unverified."
    if [[ -n $blacklist ]]; then
      extra=" The kernel command line blacklists camera-related modules (${blacklist}). An empty camera list on that command line is not a missing sensor."
    elif [[ $pm8010 == yes ]]; then
      extra=" The kernel log mentions pm8010 and no CAMSS or sensor node. On the A16 that regulator is part of the camera power story, but this probe did not see the camera stack up. Unverified."
    fi
  fi
  printf '%s\n' "$id"
  printf '%s%s\n' "$prose" "$extra"
}

face_probe_section() {
  local title="$1" file="$2"
  printf '\n----- %s -----\n' "$title"
  if [[ -f $file ]]; then
    face_probe_redact <"$file"
  else
    printf '%s\n' "(not collected)"
  fi
}

face_probe_render() {
  local sections="$1" flags="$2" verdict_id="$3" verdict_text="$4" output="$5" source_label="$6" source_note="$7"
  local parent tmp kernel model
  parent=$(dirname -- "$output")
  [[ -d $parent ]] || face_probe_die "output directory does not exist: $parent"
  [[ -e $output && -d $output ]] && face_probe_die "output path is a directory: $output"
  tmp=$(mktemp "$parent/.delight-face-probe.XXXXXX")
  kernel=$(head -n 1 -- "$sections/uname.txt" 2>/dev/null || printf '%s' "(unknown)")
  model=$(head -n 1 -- "$sections/model.txt" 2>/dev/null || printf '%s' "(unknown)")
  {
    printf '%s\n' "Omarchy Delight face probe"
    printf 'collected: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'source: %s\n' "$source_label"
    printf '%s\n' "$source_note"
    printf '%s\n' "Serial numbers, MAC addresses, usernames, and disk UUIDs are redacted."
    printf '%s\n' "Unverified: frames were not captured and no illuminator was toggled."
    printf '\n%s\n' "Verdict id: $verdict_id"
    printf '%s\n' "$verdict_text"
    printf '\n%s\n' "Facts:"
    printf 'kernel: %s\n' "$(printf '%s\n' "$kernel" | face_probe_redact)"
    printf 'model: %s\n' "$(printf '%s\n' "$model" | face_probe_redact)"
    printf 'signals: uvc_ir=%s mipi=%s rgb=%s ir_node=%s ir_stream=%s pm8010=%s usb_named=%s uvcvideo=%s\n' \
      "$(face_probe_flag "$flags" uvc_ir)" \
      "$(face_probe_flag "$flags" mipi)" \
      "$(face_probe_flag "$flags" rgb)" \
      "$(face_probe_flag "$flags" ir_node)" \
      "$(face_probe_flag "$flags" ir_stream)" \
      "$(face_probe_flag "$flags" pm8010)" \
      "$(face_probe_flag "$flags" usb_named)" \
      "$(face_probe_flag "$flags" uvcvideo)"
    local listed
    listed=$(face_probe_flag "$flags" blacklist)
    if [[ -n $listed ]]; then
      printf 'cmdline camera blacklist: %s\n' "$listed"
    else
      printf '%s\n' "cmdline camera blacklist: (none noted)"
    fi
    printf '\n%s\n' "Collected output:"
    face_probe_section "uname -r" "$sections/uname.txt"
    face_probe_section "/proc/device-tree/model" "$sections/model.txt"
    face_probe_section "device-tree camera nodes" "$sections/dt-nodes.txt"
    face_probe_section "/proc/cmdline" "$sections/cmdline.txt"
    face_probe_section "lsusb" "$sections/lsusb.txt"
    face_probe_section "uvcvideo (/sys/bus/usb/drivers/uvcvideo)" "$sections/uvcvideo.txt"
    face_probe_section "v4l2-ctl --list-devices" "$sections/v4l2.txt"
    face_probe_section "media-ctl -p (every /dev/media*)" "$sections/media.txt"
    face_probe_section "dmesg (himax|hm1092|ov02c10|camss|cci|pm8010)" "$sections/dmesg.txt"
    face_probe_section "cam -l" "$sections/cam.txt"
    face_probe_section "/sys/class/leds names" "$sections/leds.txt"
  } >"$tmp"
  chmod 600 -- "$tmp"
  mv -f -- "$tmp" "$output"
}

face_probe_main() {
  local output="" fixture=""
  while (($#)); do
    case "$1" in
      --output | -o)
        shift
        [[ -n ${1:-} ]] || face_probe_die "missing path after --output" 64
        output="$1"
        ;;
      --fixture)
        shift
        [[ -n ${1:-} ]] || face_probe_die "missing directory after --fixture" 64
        fixture="$1"
        ;;
      -h | --help | help)
        face_probe_usage
        return 0
        ;;
      *)
        face_probe_die "unknown argument '$1' (see: delight face probe --help)" 64
        ;;
    esac
    shift
  done
  if [[ -n $fixture && ! -d $fixture ]]; then
    face_probe_die "fixture directory not found: $fixture" 64
  fi
  [[ -n $output ]] || output="$PWD/delight-face-probe.txt"

  local work quoted
  work=$(mktemp -d)
  printf -v quoted '%q' "$work"
  # shellcheck disable=SC2064
  trap "rm -rf $quoted" EXIT
  mkdir -p -- "$work/sections"
  local source_label source_note
  if [[ -n $fixture ]]; then
    cp -a -- "$fixture"/. "$work/sections"/
    source_label="fixture $(basename -- "$fixture")"
    source_note="This report was built from canned fixture output, not from a live machine. It is not hardware evidence."
  else
    face_probe_collect_live "$work/sections"
    source_label="live"
    source_note="Commands were read on this boot. This is not a measurement of frame capture or of the IR illuminator."
  fi
  face_probe_classify "$work/sections" >"$work/flags"
  local verdict_id verdict_text
  verdict_id=$(face_probe_verdict "$work/flags" | head -n 1)
  verdict_text=$(face_probe_verdict "$work/flags" | tail -n +2)
  face_probe_render "$work/sections" "$work/flags" "$verdict_id" "$verdict_text" "$output" "$source_label" "$source_note"
  printf 'Verdict id: %s\n%s\n\nWrote redacted report: %s\n' "$verdict_id" "$verdict_text" "$output"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  face_probe_main "$@"
fi
