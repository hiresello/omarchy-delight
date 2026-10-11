pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Delight"

// Control Center: one tile per $XDG_RUNTIME_DIR/omarchy-delight/status/*.json.
// Clicking a tile runs `delight <id> toggle`; the chevron runs the status's
// first action, or `delight <id> open`.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var modules: []
  property bool opened: false

  readonly property string statusDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-delight/status"

  function open(payloadJson) {
    opened = true
    refresh()
  }

  function close() {
    opened = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("delight.control-center")
    else close()
  }

  function refresh() {
    if (!reader.running) reader.running = true
  }

  function parse(text) {
    let list = []
    try {
      const parsed = JSON.parse(text || "[]")
      if (Array.isArray(parsed)) list = parsed.filter(function(s) { return s && typeof s.id === "string" })
    } catch (e) {
      console.warn("delight.control-center: bad status JSON", e)
    }
    list.sort(function(a, b) { return a.id < b.id ? -1 : a.id > b.id ? 1 : 0 })
    modules = list
  }

  function run(command) {
    Quickshell.execDetached(command)
    refreshSoon.restart()
  }

  function toggle(status) {
    run(["delight", status.id, "toggle"])
  }

  function detail(status) {
    const actions = status.actions || []
    if (actions.length > 0 && Array.isArray(actions[0].command)) run(actions[0].command)
    else run(["delight", status.id, "open"])
  }

  Process {
    id: reader
    command: ["sh", "-c", "cat -- \"$1\"/*.json 2>/dev/null | jq -cs . 2>/dev/null || echo []", "sh", root.statusDir]
    stdout: StdioCollector {
      onStreamFinished: root.parse(this.text)
    }
  }

  // Fallback polling; modules also rewrite their status file on every change.
  Timer {
    interval: 2000
    repeat: true
    running: root.opened
    onTriggered: root.refresh()
  }

  Timer {
    id: refreshSoon
    interval: 300
    onTriggered: root.refresh()
  }

  // qmllint's Quickshell type info marks PanelWindow uncreatable; the shell creates it fine.
  // qmllint disable uncreatable-type missing-property
  PanelWindow {
    id: window
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "delight-control-center"

    anchors {
      top: true
      right: true
    }
    margins {
      top: 8
      right: 8
    }

    implicitWidth: sheet.implicitWidth
    implicitHeight: sheet.implicitHeight

    Sheet {
      id: sheet
      anchors.fill: parent
      title: "Control Center"
      focus: true
      Keys.onEscapePressed: root.requestClose()

      Text {
        visible: root.modules.length === 0
        text: "No Delight modules installed yet."
        color: Tokens.muted
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSize
      }

      Grid {
        columns: 2
        spacing: Tokens.spacing
        visible: root.modules.length > 0

        Repeater {
          model: root.modules

          Tile {
            required property var modelData
            width: (sheet.width - Tokens.padding * 2 - Tokens.spacing) / 2
            icon: modelData.icon || ""
            title: modelData.title || modelData.id
            subtitle: modelData.state === "unsupported" || modelData.state === "error"
              ? (modelData.reason || modelData.subtitle || "")
              : (modelData.subtitle || "")
            status: modelData.state || "off"
            toggleable: modelData.toggle !== false
            hasDetail: true
            onToggled: root.toggle(modelData)
            onDetailRequested: root.detail(modelData)
          }
        }
      }
    }
  }
}
