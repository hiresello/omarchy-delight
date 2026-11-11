#!/bin/bash

# IR face bridge. GStreamer is the capture path: libcamerasrc selects the
# HM1092 by its libcamera id, videoconvert produces GRAY8, and v4l2sink writes
# a v4l2loopback device Howdy Next can open. The libcamera Python API is not
# used; it would need a custom V4L2 writer, and CI can stand in for libcamerasrc
# with videotestsrc in this same graph.
#
# The sensor streams only while `bridge` is running. The systemd socket listens
# without opening the camera. Real HM1092 frames are unverified.

FACE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DELIGHT_FACE_BIN=$FACE_DIR/bin/delight-face

face_sensor() {
  local sensor
  sensor=$(delight_config_get face sensor 2>/dev/null || true)
  [[ -n $sensor ]] || sensor=hm1092
  [[ $sensor =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || sensor=hm1092
  printf '%s\n' "$sensor"
}

face_device_name() {
  local name
  name=$(delight_config_get face deviceName 2>/dev/null || true)
  [[ -n $name ]] || name="Delight IR"
  printf '%s\n' "$name"
}

face_device_path() {
  local path
  path=$(delight_config_get face devicePath 2>/dev/null || true)
  [[ -n $path ]] || path=/dev/v4l/by-id/delight-ir
  printf '%s\n' "$path"
}

face_max_seconds() {
  local value
  if [[ -n ${DELIGHT_FACE_MAX_SECONDS:-} ]]; then
    value=$DELIGHT_FACE_MAX_SECONDS
  else
    value=$(delight_config_get face maxSeconds 2>/dev/null || true)
  fi
  [[ $value =~ ^[0-9]+$ ]] || value=30
  ((value < 1)) && value=1
  ((value > 300)) && value=300
  printf '%s\n' "$value"
}

face_source() {
  printf '%s\n' "${DELIGHT_FACE_SOURCE:-libcamera}"
}

face_sink() {
  printf '%s\n' "${DELIGHT_FACE_SINK:-v4l2}"
}

face_sysfs() {
  printf '%s\n' "${DELIGHT_SYSFS:-/sys}"
}

face_dev_root() {
  printf '%s\n' "${DELIGHT_FACE_DEV_ROOT:-/dev}"
}

face_user_runtime() {
  printf '%s\n' "${XDG_RUNTIME_DIR:-/run/user/$UID}/omarchy-delight/face"
}

face_system_runtime() {
  printf '%s\n' "${DELIGHT_FACE_SYSTEM_RUNTIME:-/run/omarchy-delight}"
}

face_ready_file() {
  printf '%s\n' "$(face_user_runtime)/ready"
}

face_socket_path() {
  printf '%s\n' "${DELIGHT_FACE_SOCKET:-/run/omarchy-delight/face-bridge.sock}"
}

face_stream_error() {
  FACE_SELECT_ERROR="no IR camera stream: $*"
  printf '%s\n' "$FACE_SELECT_ERROR" >&2
}

face_pipeline_error() {
  printf '%s\n' "IR bridge failed: $*" >&2
}

# Read cam -l-style lines on stdin. Append libcamera ids for the sensor.
# A numeric index is never an id.
face_collect_ids() {
  local sensor="$1" sensor_lower line lower id id_re index_re
  # Stored so the ")" inside the pattern does not confuse shellcheck.
  id_re='\((/[^)]+)\)'
  index_re='^[[:space:]]*[0-9]+[[:space:]]*:'
  sensor_lower=${sensor,,}
  FACE_IDS=()
  while IFS= read -r line || [[ -n $line ]]; do
    lower=${line,,}
    [[ $lower == *"$sensor_lower"* ]] || continue
    id=""
    if [[ $line =~ $id_re ]]; then
      id=${BASH_REMATCH[1]}
    elif [[ $line =~ $index_re ]]; then
      face_stream_error "a libcamera line mentions sensor '${sensor}' but has no camera id. Refusing to choose a camera by index."
      return 1
    else
      continue
    fi
    if [[ $id =~ ^[0-9]+$ || $id != /* ]]; then
      face_stream_error "sensor '${sensor}' resolved to a camera index. Refusing to choose a camera by index."
      return 1
    fi
    FACE_IDS+=("$id")
  done
}

face_ids_unique() {
  local id
  local -A seen=()
  local -a uniq=()
  ((${#FACE_IDS[@]} == 0)) && return 0
  for id in "${FACE_IDS[@]}"; do
    [[ -n ${seen[$id]+x} ]] && continue
    seen[$id]=1
    uniq+=("$id")
  done
  FACE_IDS=("${uniq[@]}")
}

face_read_cam_list() {
  local sensor="$1" list err rc
  if [[ -n ${DELIGHT_FACE_CAM_LIST:-} ]]; then
    if [[ ! -f $DELIGHT_FACE_CAM_LIST ]]; then
      face_stream_error "camera list '${DELIGHT_FACE_CAM_LIST}' is not readable."
      return 1
    fi
    face_collect_ids "$sensor" <"$DELIGHT_FACE_CAM_LIST"
    return
  fi
  if ! command -v cam >/dev/null 2>&1; then
    face_stream_error "cam is not installed, so sensor '${sensor}' cannot be selected by name. Install libcamera-tools."
    return 1
  fi
  list=$(mktemp)
  err=$(mktemp)
  if ! cam -l >"$list" 2>"$err"; then
    face_stream_error "cam -l failed, so sensor '${sensor}' cannot be selected by name."
    rm -f -- "$list" "$err"
    return 1
  fi
  face_collect_ids "$sensor" <"$list"
  rc=$?
  rm -f -- "$list" "$err"
  return "$rc"
}

# Print the libcamera id of the named sensor. Never prints an index.
face_select_camera() {
  local sensor="$1"
  FACE_SELECT_ERROR=
  FACE_IDS=()
  face_read_cam_list "$sensor" || return 1
  face_ids_unique
  if ((${#FACE_IDS[@]} == 0)); then
    face_stream_error "no libcamera camera matches sensor '${sensor}'. Refusing to choose a camera by index. Real HM1092 output is unverified; this is the expected result until the sensor is streaming on the A16."
    return 1
  fi
  if ((${#FACE_IDS[@]} > 1)); then
    face_stream_error "more than one libcamera camera matches sensor '${sensor}'. Refusing to choose one by index."
    return 1
  fi
  printf '%s\n' "${FACE_IDS[0]}"
}

face_prepare_capture() {
  local sensor id source
  FACE_CAMERA_ID=
  source=$(face_source)
  case "$source" in
    videotestsrc) return 0 ;;
    libcamera)
      sensor=$(face_sensor)
      id=$(face_select_camera "$sensor") || return 1
      [[ -n $id && $id == /* ]] || {
        face_stream_error "sensor '${sensor}' did not resolve to a libcamera id path. Refusing to choose a camera by index."
        return 1
      }
      FACE_CAMERA_ID=$id
      ;;
    *)
      face_stream_error "unknown capture source '${source}'. Use libcamera, or videotestsrc for the synthetic stand-in."
      return 1
      ;;
  esac
}

face_build_pipeline() {
  local gst source sink caps
  source=$(face_source)
  sink=$(face_sink)
  gst=${DELIGHT_FACE_GST:-gst-launch-1.0}
  FACE_ARGV=("$gst" -e)
  if [[ $source == videotestsrc ]]; then
    FACE_ARGV+=(videotestsrc "pattern=${DELIGHT_FACE_PATTERN:-ball}")
    if [[ -n ${DELIGHT_FACE_NUM_BUFFERS:-} ]]; then
      FACE_ARGV+=("num-buffers=${DELIGHT_FACE_NUM_BUFFERS}")
    fi
    if [[ ${DELIGHT_FACE_LIVE:-true} == true ]]; then
      FACE_ARGV+=(is-live=true)
    fi
    caps="video/x-raw,format=GRAY8"
    if [[ -n ${DELIGHT_FACE_WIDTH:-} && ${DELIGHT_FACE_WIDTH} != 0 ]]; then
      caps+=",width=${DELIGHT_FACE_WIDTH},height=${DELIGHT_FACE_HEIGHT}"
    fi
    caps+=",framerate=${DELIGHT_FACE_FRAMERATE:-30/1}"
    FACE_ARGV+=('!' "$caps")
  else
    [[ -n ${FACE_CAMERA_ID:-} ]] || return 1
    FACE_ARGV+=(libcamerasrc "camera-name=${FACE_CAMERA_ID}" '!' videoconvert '!' 'video/x-raw,format=GRAY8')
  fi
  FACE_ARGV+=('!')
  case "$sink" in
    filesink)
      [[ -n ${DELIGHT_FACE_SINK_LOCATION:-} ]] || return 1
      FACE_ARGV+=(filesink "location=${DELIGHT_FACE_SINK_LOCATION}")
      ;;
    fakesink)
      FACE_ARGV+=(fakesink)
      ;;
    v4l2)
      FACE_ARGV+=(v4l2sink "device=$(face_device_path)" sync=false)
      ;;
    *)
      face_pipeline_error "unknown sink '${sink}'."
      return 1
      ;;
  esac
}

face_device_by_name() {
  local name name_file label
  name=$(face_device_name)
  for name_file in "$(face_sysfs)"/devices/virtual/video4linux/video*/name; do
    [[ -f $name_file ]] || continue
    IFS= read -r label <"$name_file" || true
    if [[ $label == "$name" ]]; then
      basename -- "$(dirname -- "$name_file")"
      return 0
    fi
  done
  return 1
}

face_link_path() {
  local path base
  path=$(face_device_path)
  base=${path##*/}
  printf '%s\n' "$(face_dev_root)/v4l/by-id/${base}"
}

face_ensure_device() {
  local name video link
  name=$(face_device_name)
  if video=$(face_device_by_name); then
    :
  else
    if [[ ! -d $(face_sysfs)/module/v4l2loopback ]]; then
      delight_run sudo modprobe v4l2loopback devices=0 || {
        face_pipeline_error "v4l2loopback could not be loaded, so there is no grey device for Howdy Next."
        return 1
      }
    fi
    delight_run sudo v4l2loopback-ctl add -n "$name" -x 1 || {
      face_pipeline_error "the grey loopback device '${name}' could not be created."
      return 1
    }
    video=$(face_device_by_name) || {
      face_pipeline_error "the grey loopback device '${name}' did not appear. Refusing to guess a /dev/video index."
      return 1
    }
  fi
  link=$(face_link_path)
  delight_run sudo mkdir -p -- "$(dirname -- "$link")" || return 1
  delight_run sudo ln -sfn -- "/dev/${video}" "$link" || return 1
  printf '%s\n' "$video"
}

face_delete_loopback_device() {
  local video link target
  video=$(face_device_by_name) || return 0
  link=$(face_link_path)
  if [[ -L $link ]]; then
    target=$(readlink -- "$link" 2>/dev/null || true)
    if [[ $target == "/dev/$video" ]]; then
      delight_run sudo rm -f -- "$link" || delight_warn "face: could not remove $link"
    fi
  fi
  if ! command -v v4l2loopback-ctl >/dev/null 2>&1; then
    return 0
  fi
  delight_run sudo v4l2loopback-ctl delete "/dev/$video" \
    || delight_warn "face: could not delete the Delight IR loopback"
}

face_cleanup_gst() {
  local pidfile
  if [[ -n ${FACE_GST_PID:-} ]]; then
    kill -TERM "$FACE_GST_PID" 2>/dev/null || true
    wait "$FACE_GST_PID" 2>/dev/null || true
    FACE_GST_PID=
  fi
  for pidfile in "$(face_user_runtime)/gst.pid" "$(face_system_runtime)/gst.pid"; do
    rm -f -- "$pidfile" 2>/dev/null || true
  done
  rm -f -- "$(face_ready_file)" 2>/dev/null || true
}

face_write_gst_pid() {
  local runtime pidfile
  runtime=$(face_user_runtime)
  mkdir -p -- "$runtime"
  pidfile=$runtime/gst.pid
  printf '%s\n' "$FACE_GST_PID" >"$pidfile"
  if [[ -w $(face_system_runtime) || $EUID -eq 0 ]]; then
    mkdir -p -- "$(face_system_runtime)" 2>/dev/null || true
    if [[ -w $(face_system_runtime) ]]; then
      printf '%s\n' "$FACE_GST_PID" >"$(face_system_runtime)/gst.pid"
    fi
  fi
}

face_wait_gst() {
  local sink location i format_file video
  sink=$(face_sink)
  location=${DELIGHT_FACE_SINK_LOCATION:-}
  for ((i = 0; i < 30; i++)); do
    if [[ -z ${FACE_GST_PID:-} ]] || ! kill -0 "$FACE_GST_PID" 2>/dev/null; then
      return 1
    fi
    if [[ $sink == fakesink ]]; then
      return 0
    fi
    if [[ $sink == filesink && -n $location && -s $location ]]; then
      return 0
    fi
    if [[ $sink == v4l2 ]]; then
      video=$(face_device_by_name || true)
      format_file="$(face_sysfs)/devices/virtual/video4linux/${video}/format"
      if [[ -n $video && -s $format_file ]]; then
        return 0
      fi
      # The format file is not present on every v4l2loopback. A live process
      # after a short wait is the best userspace signal that v4l2sink opened it.
      if ((i >= 5)); then
        return 0
      fi
    fi
    sleep 0.1
  done
  [[ -n ${FACE_GST_PID:-} ]] && kill -0 "$FACE_GST_PID" 2>/dev/null
}

face_bridge_wait() {
  local deadline rc
  deadline=$((SECONDS + $(face_max_seconds)))
  while ((SECONDS < deadline)); do
    if [[ -n ${FACE_GST_PID:-} ]] && ! kill -0 "$FACE_GST_PID" 2>/dev/null; then
      return 0
    fi
    # A fractional `read -t` on bash 5.2 returns immediately and never observes
    # EOF, so the sensor would keep streaming until maxSeconds. An integer
    # timeout reports a client line as 0 and a closed stream as 1.
    if IFS= read -r -t 1 _; then
      return 0
    fi
    rc=$?
    if ((rc == 1)); then
      return 0
    fi
  done
}

face_say() {
  /bin/echo "$*"
}

face_run_pipeline_capture() {
  local log="$1"
  face_build_pipeline || return 1
  if ! command -v "${FACE_ARGV[0]}" >/dev/null 2>&1 && [[ ! -x ${FACE_ARGV[0]} ]]; then
    face_pipeline_error "gst-launch-1.0 is not installed, so the grey pipeline cannot run."
    return 1
  fi
  "${FACE_ARGV[@]}" >"$log" 2>&1
}

module_select() {
  face_select_camera "$(face_sensor)"
}

module_pipeline() {
  face_prepare_capture || return 1
  face_build_pipeline || return 1
  printf '%q ' "${FACE_ARGV[@]}"
  printf '\n'
}

module_self_test() {
  local dir log size expect rc=0
  # Always the real gst-launch. A test stub left in the environment must not
  # stand in for the grey-frame check.
  unset DELIGHT_FACE_GST
  dir=$(mktemp -d)
  log=$dir/gst.log
  DELIGHT_FACE_SOURCE=videotestsrc
  DELIGHT_FACE_SINK=filesink
  DELIGHT_FACE_SINK_LOCATION=$dir/frame.raw
  DELIGHT_FACE_NUM_BUFFERS=1
  DELIGHT_FACE_WIDTH=16
  DELIGHT_FACE_HEIGHT=16
  DELIGHT_FACE_PATTERN=white
  DELIGHT_FACE_FRAMERATE=1/1
  DELIGHT_FACE_LIVE=false
  export DELIGHT_FACE_SOURCE DELIGHT_FACE_SINK DELIGHT_FACE_SINK_LOCATION
  export DELIGHT_FACE_NUM_BUFFERS DELIGHT_FACE_WIDTH DELIGHT_FACE_HEIGHT
  export DELIGHT_FACE_PATTERN DELIGHT_FACE_FRAMERATE DELIGHT_FACE_LIVE
  if ! face_run_pipeline_capture "$log"; then
    face_pipeline_error "the synthetic grey pipeline exited before a frame was available. Real HM1092 output is unverified."
    tail -n 20 "$log" >&2 || true
    rc=1
  else
    if [[ ! -s $DELIGHT_FACE_SINK_LOCATION ]]; then
      face_pipeline_error "the synthetic grey pipeline produced no frame. Real HM1092 output is unverified."
      rc=1
    else
      size=$(wc -c <"$DELIGHT_FACE_SINK_LOCATION" | tr -d ' ')
      if [[ $size != 256 ]]; then
        face_pipeline_error "grey sample was ${size} bytes, expected 256 (GRAY8 16x16). Real HM1092 output is unverified."
        rc=1
      else
        expect=$dir/white.raw
        # videotestsrc pattern=white in GRAY8 is studio white (235), one byte per pixel.
        # 16x16 is 256 bytes; a 3-channel frame would be 768 and would not match.
        dd if=/dev/zero bs=256 count=1 status=none | tr '\0' '\353' >"$expect"
        if ! cmp -s "$expect" "$DELIGHT_FACE_SINK_LOCATION"; then
          face_pipeline_error "grey sample was 256 bytes but not a uniform GRAY8 frame. Real HM1092 output is unverified."
          rc=1
        else
          printf '%s\n' "grey-sample ok bytes=${size} format=GRAY8 source=videotestsrc"
          printf '%s\n' "note: videotestsrc stand-in. Real HM1092 output is unverified until this runs on the A16."
        fi
      fi
    fi
  fi
  rm -rf -- "$dir"
  return "$rc"
}

module_bridge() {
  local log ready path video
  trap face_cleanup_gst EXIT
  # SIGTERM does not run an EXIT trap. stop sends TERM to the hold group.
  trap 'face_cleanup_gst; exit 143' TERM INT
  rm -f -- "$(face_ready_file)"
  mkdir -p -- "$(face_user_runtime)"
  if ! face_prepare_capture; then
    face_say "error ${FACE_SELECT_ERROR:-no IR camera stream: the HM1092 could not be selected.}"
    return 1
  fi
  if [[ $(face_source) == videotestsrc ]]; then
    printf '%s\n' "note: source is videotestsrc, not the HM1092. Real HM1092 output is unverified." >&2
  fi
  path=$(face_device_path)
  if [[ $(face_sink) == v4l2 ]]; then
    video=$(face_ensure_device) || {
      face_say "error IR bridge failed: the grey loopback device could not be created. Real HM1092 output is unverified."
      return 1
    }
    path=$(face_device_path)
  fi
  log=$(face_user_runtime)/gst.log
  face_build_pipeline || {
    face_say "error IR bridge failed: the capture pipeline could not be built. Real HM1092 output is unverified."
    return 1
  }
  if ! command -v "${FACE_ARGV[0]}" >/dev/null 2>&1 && [[ ! -x ${FACE_ARGV[0]} ]]; then
    face_say "error IR bridge failed: gst-launch-1.0 is not installed. Real HM1092 output is unverified."
    return 1
  fi
  "${FACE_ARGV[@]}" >"$log" 2>&1 &
  FACE_GST_PID=$!
  face_write_gst_pid
  if ! face_wait_gst; then
    face_pipeline_error "the capture pipeline exited before a grey frame was available. Real HM1092 output is unverified."
    tail -n 20 "$log" >&2 || true
    face_say "error IR bridge failed: the capture pipeline exited before a grey frame was available. Real HM1092 output is unverified."
    return 1
  fi
  ready=$(face_ready_file)
  printf '%s\n' "$path" >"$ready"
  face_say "ready $path"
  face_bridge_wait
  face_cleanup_gst
  return 0
}

face_hold_direct() {
  local dir in_fifo bridge_pid line device cmd_rc max i
  dir=$(mktemp -d)
  in_fifo=$dir/in
  mkfifo "$in_fifo"
  max=$(face_max_seconds)
  "$DELIGHT_FACE_BIN" bridge <"$in_fifo" >"$dir/out" 2>"$dir/err" &
  bridge_pid=$!
  exec {in_fd}>"$in_fifo"
  line=""
  for ((i = 0; i < max * 10; i++)); do
    if [[ -s $dir/out ]]; then
      IFS= read -r line <"$dir/out" || true
      break
    fi
    if ! kill -0 "$bridge_pid" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done
  if [[ $line != ready\ * ]]; then
    exec {in_fd}>&- || true
    wait "$bridge_pid" 2>/dev/null || true
    if [[ -s $dir/err ]]; then
      cat -- "$dir/err" >&2
    fi
    rm -rf -- "$dir"
    if [[ $line == error\ * ]]; then
      delight_die "${line#error }"
    fi
    delight_die "IR bridge failed: no ready line. Real HM1092 output is unverified."
  fi
  device=${line#ready }
  printf '%s\n' "$device" >&2
  cmd_rc=0
  "$@" || cmd_rc=$?
  # A newline is the stop signal. Closing the fifo is the backup.
  printf '\n' >&"$in_fd" || true
  exec {in_fd}>&- || true
  wait "$bridge_pid" 2>/dev/null || true
  rm -rf -- "$dir"
  return "$cmd_rc"
}

face_hold_socket() {
  local sock dir in_fifo nc_pid line device cmd_rc max i
  local -a nc_args
  sock=$(face_socket_path)
  max=$(face_max_seconds)
  dir=$(mktemp -d)
  in_fifo=$dir/in
  mkfifo "$in_fifo"
  # -N makes OpenBSD nc close the socket when the hold ends, which stops the bridge.
  nc_args=(-U "$sock")
  if nc -h 2>&1 | grep -q -- '-N'; then
    nc_args=(-N -U "$sock")
  fi
  nc "${nc_args[@]}" <"$in_fifo" >"$dir/out" 2>"$dir/err" &
  nc_pid=$!
  exec {in_fd}>"$in_fifo"
  line=""
  for ((i = 0; i < max * 10; i++)); do
    if [[ -s $dir/out ]]; then
      IFS= read -r line <"$dir/out" || true
      break
    fi
    if ! kill -0 "$nc_pid" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done
  if [[ $line != ready\ * ]]; then
    exec {in_fd}>&- || true
    wait "$nc_pid" 2>/dev/null || true
    if [[ -s $dir/err ]]; then
      cat -- "$dir/err" >&2
    fi
    rm -rf -- "$dir"
    if [[ $line == error\ * ]]; then
      delight_die "${line#error }"
    fi
    delight_die "IR bridge failed: the system bridge did not become ready. Real HM1092 output is unverified."
  fi
  device=${line#ready }
  printf '%s\n' "$device" >&2
  cmd_rc=0
  "$@" || cmd_rc=$?
  printf '\n' >&"$in_fd" || true
  exec {in_fd}>&- || true
  wait "$nc_pid" 2>/dev/null || true
  rm -rf -- "$dir"
  return "$cmd_rc"
}

face_hold() {
  local sock runtime
  # arm records this shell, not the setsid wrapper. setsid forks when it is
  # already a process-group leader, and $! is then the wrapper that exits.
  if [[ ${DELIGHT_FACE_ARM:-0} == 1 ]]; then
    runtime=$(face_user_runtime)
    mkdir -p -- "$runtime"
    printf '%s\n' "$$" >"$runtime/arm.pid"
    trap 'exit 143' TERM INT HUP
  fi
  sock=$(face_socket_path)
  if [[ ${DELIGHT_FACE_DIRECT:-0} != 1 && -S $sock ]]; then
    if command -v nc >/dev/null 2>&1; then
      face_hold_socket "$@"
      return
    fi
    delight_warn "face: nc is not available; starting a direct bridge instead of the system socket"
  fi
  face_hold_direct "$@"
}

module_hold() {
  if [[ ${1:-} != "--" ]]; then
    delight_die "usage: delight face hold -- <command> [args...]" 64
  fi
  shift
  (($# > 0)) || delight_die "usage: delight face hold -- <command> [args...]" 64
  face_hold "$@"
}

# True while the pid is a live process. A zombie is already dead: kill -0
# still succeeds, and a container PID 1 that never waits leaves it visible.
face_pid_running() {
  local pid=$1 state
  [[ $pid =~ ^[0-9]+$ ]] || return 1
  [[ -r /proc/$pid/stat ]] || return 1
  # comm is wrapped in parentheses and may contain spaces. The state is the
  # first field after the closing parenthesis.
  state=$(sed -n 's/.*) //p' "/proc/$pid/stat" 2>/dev/null || true)
  state=${state%% *}
  [[ -n $state && $state != Z ]]
}

# Signal pid and its children. Process-group kill is not enough: a setsid
# wrapper can be a different pid from the hold shell, and some bash builds
# do not treat `kill -pgid` as a fallback for the pid itself.
face_kill_tree() {
  local pid=$1 sig=$2 child
  local -a children=()
  [[ $pid =~ ^[0-9]+$ ]] || return 0
  if command -v ps >/dev/null 2>&1; then
    # Default IFS so `read` strips the leading spaces `ps -o pid=` prints.
    # An empty IFS keeps those spaces and the pid check skips every child.
    while read -r child; do
      [[ $child =~ ^[0-9]+$ ]] || continue
      children+=("$child")
    done < <(ps -o pid= --ppid "$pid" 2>/dev/null || true)
  fi
  for child in "${children[@]+"${children[@]}"}"; do
    face_kill_tree "$child" "$sig"
  done
  kill -s "$sig" -- "$pid" 2>/dev/null || true
}

face_stop_pid() {
  local pid=$1 i
  face_pid_running "$pid" || return 0
  face_kill_tree "$pid" TERM
  for ((i = 0; i < 20; i++)); do
    face_pid_running "$pid" || return 0
    sleep 0.05
  done
  face_kill_tree "$pid" KILL
}

face_stop_processes() {
  local pidfile pid
  for pidfile in "$(face_user_runtime)/arm.pid" "$(face_user_runtime)/gst.pid" "$(face_system_runtime)/gst.pid"; do
    [[ -f $pidfile ]] || continue
    pid=$(cat -- "$pidfile" 2>/dev/null || true)
    face_stop_pid "$pid"
    rm -f -- "$pidfile"
  done
  rm -f -- "$(face_ready_file)"
}

module_arm() {
  local runtime pidfile out err pid i ready
  runtime=$(face_user_runtime)
  pidfile=$runtime/arm.pid
  out=$runtime/arm.out
  err=$runtime/arm.err
  mkdir -p -- "$runtime"
  if [[ -f $pidfile ]]; then
    pid=$(cat -- "$pidfile" 2>/dev/null || true)
    if face_pid_running "$pid"; then
      printf '%s\n' "already streaming"
      return 0
    fi
  fi
  rm -f -- "$(face_ready_file)" "$out" "$err" "$pidfile"
  # The hold shell overwrites arm.pid with its own $$.
  if command -v setsid >/dev/null 2>&1; then
    DELIGHT_FACE_ARM=1 setsid "$DELIGHT_FACE_BIN" hold -- sleep "$(face_max_seconds)" >"$out" 2>"$err" &
  else
    DELIGHT_FACE_ARM=1 "$DELIGHT_FACE_BIN" hold -- sleep "$(face_max_seconds)" >"$out" 2>"$err" &
  fi
  ready=$(face_ready_file)
  for ((i = 0; i < $(face_max_seconds) * 10; i++)); do
    if [[ -s $ready ]]; then
      cat -- "$ready"
      return 0
    fi
    if [[ -s $pidfile ]]; then
      pid=$(cat -- "$pidfile" 2>/dev/null || true)
      if [[ $pid =~ ^[0-9]+$ ]] && ! face_pid_running "$pid"; then
        cat -- "$err" >&2 || true
        rm -f -- "$pidfile"
        return 1
      fi
    fi
    sleep 0.1
  done
  if [[ -s $pidfile ]]; then
    pid=$(cat -- "$pidfile" 2>/dev/null || true)
    face_stop_pid "$pid"
  fi
  rm -f -- "$pidfile"
  face_stream_error "the bridge did not become ready. Real HM1092 output is unverified."
  return 1
}

module_stop() {
  face_stop_processes
}

module_ensure() {
  face_ensure_device >/dev/null
  face_device_path
}

face_system_files() {
  delight_state_get face | jq -r '.flags.systemFiles[]?'
}

face_system_units_installed() {
  delight_state_get face | jq -e '.flags.systemFiles | type == "array" and length > 0' >/dev/null
}

face_install_rendered() {
  local dest="$1" content="$2" tmp
  if delight_dry; then
    delight_dry_print sudo install -Dm644 "<rendered>" "$dest"
    return 0
  fi
  tmp=$(mktemp)
  printf '%s\n' "$content" >"$tmp"
  delight_run sudo install -Dm644 "$tmp" "$dest"
  rm -f -- "$tmp"
}

face_render_service() {
  local content root
  root=$DELIGHT_ROOT
  content=$(cat -- "$FACE_DIR/system/delight-face-bridge@.service.in")
  content=${content//@ROOT@/$root}
  printf '%s\n' "$content"
}

face_install_kernel_headers() {
  local root pkgbase_file pkgbase header found=0
  local -A seen=()
  root=${DELIGHT_FACE_MODULES_ROOT:-/usr/lib/modules}
  [[ -d $root ]] || {
    delight_log "face: no kernel module directory at $root"
    return 0
  }
  for pkgbase_file in "$root"/*/pkgbase; do
    [[ -f $pkgbase_file ]] || continue
    found=1
    IFS= read -r pkgbase <"$pkgbase_file" || true
    [[ -n $pkgbase ]] || continue
    header="${pkgbase}-headers"
    [[ -z ${seen[$header]:-} ]] || continue
    seen[$header]=1
    if delight_pkg_present "$pkgbase"; then
      delight_pkg_add face repo "$header"
    fi
  done
  if ((found == 0)); then
    delight_log "face: no kernel pkgbase files under $root"
  fi
}

face_install_system_units() {
  local unit_dir udev_dir tmp_dir socket service udev tmp rendered
  if ! delight_hw_kmod_loadable v4l2loopback; then
    delight_warn "v4l2loopback is not available for kernel $(uname -r); skipping the on-demand bridge units. Run delight face install again after it builds."
    return 0
  fi
  unit_dir=${DELIGHT_FACE_SYSTEM_UNIT_DIR:-/etc/systemd/system}
  udev_dir=${DELIGHT_FACE_UDEV_DIR:-/etc/udev/rules.d}
  tmp_dir=${DELIGHT_FACE_TMPFILES_DIR:-/etc/tmpfiles.d}
  socket=$unit_dir/delight-face-bridge.socket
  service=$unit_dir/delight-face-bridge@.service
  udev=$udev_dir/99-delight-ir.rules
  tmp=$tmp_dir/delight-face.conf
  delight_run sudo install -Dm644 "$FACE_DIR/system/delight-face-bridge.socket" "$socket"
  rendered=$(face_render_service)
  face_install_rendered "$service" "$rendered"
  delight_run sudo install -Dm644 "$FACE_DIR/udev/99-delight-ir.rules" "$udev"
  delight_run sudo install -Dm644 "$FACE_DIR/tmpfiles/delight-face.conf" "$tmp"
  delight_state_flag_set face systemFiles "$(jq -cn --arg socket "$socket" --arg service "$service" --arg udev "$udev" --arg tmp "$tmp" '[$socket,$service,$udev,$tmp]')"
  delight_run sudo systemctl daemon-reload || delight_warn "face: could not reload systemd"
}

face_remove_system_files() {
  local path removed=0
  while IFS= read -r path; do
    [[ -n $path ]] || continue
    if [[ -e $path || -L $path ]]; then
      delight_run sudo rm -f -- "$path" || delight_warn "face: could not remove $path"
    fi
    removed=1
  done < <(face_system_files)
  if ((removed == 1)); then
    delight_run sudo systemctl daemon-reload || true
  fi
}

module__listen() {
  if ! face_system_units_installed; then
    delight_log "face: system bridge is not installed; run delight face install once v4l2loopback builds"
    return 0
  fi
  delight_run sudo mkdir -p -- "$(face_system_runtime)" || delight_warn "face: could not create $(face_system_runtime)"
  # The socket only listens. The sensor stays off until a client connects.
  delight_run sudo systemctl enable --now delight-face-bridge.socket \
    || delight_warn "face: could not enable the IR bridge socket"
}

module__unlisten() {
  if ! face_system_units_installed; then
    return 0
  fi
  face_stop_processes
  delight_run sudo systemctl disable --now delight-face-bridge.socket \
    || delight_warn "face: could not disable the IR bridge socket"
}

face_bridge_active() {
  local pidfile pid
  for pidfile in "$(face_user_runtime)/gst.pid" "$(face_system_runtime)/gst.pid"; do
    [[ -f $pidfile ]] || continue
    pid=$(cat -- "$pidfile" 2>/dev/null || true)
    if [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

module_install() {
  local fragment
  face_install_kernel_headers
  delight_module_default_install
  fragment=$DELIGHT_CONFIG_DIR/face/howdy-next.ini
  delight_file_install face "$FACE_DIR/config/howdy-next.ini" "$fragment"
  face_install_system_units
}

module_uninstall() {
  face_stop_processes
  face_delete_loopback_device
  face_remove_system_files
  delight_module_default_uninstall
}

module_enable() {
  delight_module_default_enable
}

module_disable() {
  module__unlisten || true
  delight_module_default_disable
}

module_status() {
  local name icon
  name=$(delight_module_field face '.name')
  icon=$(delight_module_field face '.icon')
  if ! delight_is_installed face; then
    delight_status_json --id face --state needs-setup --title "$name" --subtitle "Not installed" --icon "$icon" \
      --actions '[{"label":"Install","command":["delight","face","install"]}]'
    return 0
  fi
  if ! delight_hw_kmod_loadable v4l2loopback; then
    delight_status_json --id face --state unsupported --title "$name" --icon "$icon" \
      --reason "v4l2loopback is not available for kernel $(uname -r); the IR bridge needs a loopback device"
    return 0
  fi
  if ! delight_module_enabled; then
    delight_status_json --id face --state off --title "$name" --subtitle "Off" --icon "$icon"
    return 0
  fi
  if face_bridge_active; then
    delight_status_json --id face --state on --title "$name" --subtitle "Streaming for a capture" --icon "$icon"
  else
    delight_status_json --id face --state on --title "$name" --subtitle "Armed — sensor off until a capture" --icon "$icon"
  fi
}

module_doctor() {
  local pkg missing=0 id
  if ! delight_is_installed face; then
    echo "face is not installed (run: delight face install)"
    return 1
  fi
  while IFS= read -r pkg; do
    [[ -n $pkg ]] || continue
    if ! delight_pkg_present "$pkg"; then
      echo "missing package: $pkg (run: delight face install)"
      missing=1
    fi
  done < <(delight_module_field face '.packages.repo[]?, .packages.aur[]?')
  if ((missing != 0)); then
    return 1
  fi
  if ! delight_hw_kmod_loadable v4l2loopback; then
    echo "unsupported: v4l2loopback is not available for kernel $(uname -r)"
    return 2
  fi
  # cam -l lists cameras. It does not start this bridge, so the privacy LED
  # stays off unless a hold or arm is already running.
  if ! id=$(face_select_camera "$(face_sensor)"); then
    return 3
  fi
  echo "libcamera lists ${id}."
  echo "Grey frames from the HM1092 are unverified until a capture is run on the A16."
  echo "Howdy Next device_path: $(face_device_path)"
  echo "Apply it with: sudo howdy set device_path $(face_device_path)"
  echo "This module does not change PAM. Keep a password."
}
