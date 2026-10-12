import QtQuick
import Quickshell

// Every command the Control Center runs, in one place. All go through the
// `delight` dispatcher; nothing here knows a module id.
QtObject {
  id: root

  property var delightCommand: ["delight"]
  property var terminalCommand: ["xdg-terminal-exec", "--app-id=delight.terminal", "--"]

  signal ran(var command)

  // Status objects that crossed a QML signal hold sequence types, not JS arrays.
  function toList(value) {
    if (!value || typeof value === "string" || typeof value.length !== "number") return []
    return Array.prototype.slice.call(value).map(String)
  }

  function run(command) {
    let argv = toList(command)
    if (argv.length === 0) return
    Quickshell.execDetached(argv)
    ran(argv)
  }

  function toggle(status) {
    run(delightCommand.concat([status.id, "toggle"]))
  }

  // "…": the module's first action, else `delight <id> open`.
  function detail(status) {
    let actions = status.actions || []
    let first = actions.length > 0 && actions[0] ? toList(actions[0].command) : []
    if (first.length > 0) run(first)
    else run(delightCommand.concat([status.id, "open"]))
  }

  function openDevice(device) {
    if (device && device.module) run(delightCommand.concat([device.module, "open"]))
  }

  // Installs may prompt for sudo, so they get a terminal.
  function install(id) {
    let script = "\"$@\" install; status=$?; echo; read -rsn1 -p 'Press any key to close'; exit $status"
    run(terminalCommand.concat(["bash", "-c", script, "delight-install"]).concat(delightCommand).concat([id]))
  }
}
