pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Delight"

// Delight share sheet. Summoned with a payload:
//   {"paths": [...], "targetsCommand": ["delight", "share", "share-targets", "--json"]}
// Selecting a target runs `delight share send <id> <paths...>` detached; the
// send itself reports progress and result via notifications.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property var paths: []
  property var targetsCommand: []
  property var targets: []
  property bool loading: false
  property int selectedIndex: 0

  readonly property string pluginId: (manifest && manifest.id) || "delight.share"

  function open(payloadJson) {
    try {
      const payload = JSON.parse(payloadJson || "{}")
      root.paths = Array.isArray(payload.paths) ? payload.paths : []
      root.targetsCommand = Array.isArray(payload.targetsCommand) && payload.targetsCommand.length > 0
        ? payload.targetsCommand
        : ["delight", "share", "share-targets", "--json"]
    } catch (e) {
      root.paths = []
      root.targetsCommand = ["delight", "share", "share-targets", "--json"]
    }
    root.opened = true
    root.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function refresh() {
    if (!scanner.running) {
      root.loading = true
      scanner.running = true
    }
  }

  function parseTargets(text) {
    root.loading = false
    let list = []
    try {
      const parsed = JSON.parse(text || "[]")
      if (Array.isArray(parsed))
        list = parsed.filter(function(t) { return t && typeof t.id === "string" && typeof t.label === "string" })
    } catch (e) {
      console.warn("delight.share: bad targets JSON", e)
    }
    root.targets = list
    if (root.selectedIndex >= list.length)
      root.selectedIndex = Math.max(0, list.length - 1)
  }

  function kindGlyph(kind) {
    switch (kind) {
    case "phone": return "󰄜"
    case "laptop": return "󰌢"
    case "web": return "󰖟"
    default: return "󰒋"
    }
  }

  function send(target) {
    const argv = ["delight", "share", "send", target.id].concat(root.paths)
    Quickshell.execDetached(argv)
    root.dismiss()
  }

  function sendSelected() {
    if (root.targets.length > 0 && root.selectedIndex < root.targets.length)
      root.send(root.targets[root.selectedIndex])
  }

  function move(delta) {
    const n = root.targets.length
    if (n === 0)
      return
    root.selectedIndex = ((root.selectedIndex + delta) % n + n) % n
  }

  Process {
    id: scanner
    command: root.targetsCommand.length > 0 ? root.targetsCommand : ["true"]
    stdout: StdioCollector {
      onStreamFinished: root.parseTargets(this.text)
    }
  }

  // qmllint's Quickshell type info marks PanelWindow uncreatable; the shell creates it fine.
  // qmllint disable uncreatable-type missing-property
  PanelWindow {
    id: window
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "delight-share"

    anchors {
      top: true
      right: true
      bottom: true
      left: true
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(Tokens.background.r, Tokens.background.g, Tokens.background.b, 0.6)

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    Item {
      id: keyCatcher
      anchors.centerIn: parent
      width: sheet.implicitWidth
      height: sheet.implicitHeight
      focus: true

      Keys.onEscapePressed: root.dismiss()
      Keys.onReturnPressed: root.sendSelected()
      Keys.onEnterPressed: root.sendSelected()
      Keys.onSpacePressed: root.sendSelected()
      Keys.onLeftPressed: root.move(-1)
      Keys.onRightPressed: root.move(1)
      Keys.onUpPressed: root.move(-grid.columns)
      Keys.onDownPressed: root.move(grid.columns)
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_R)
          root.refresh()
        else if (event.key === Qt.Key_Tab)
          root.move(event.modifiers & Qt.ShiftModifier ? -1 : 1)
      }

      Sheet {
        id: sheet
        anchors.fill: parent
        title: "Share"

        implicitWidth: 420

        Row {
          spacing: Tokens.spacing

          Rectangle {
            width: 40
            height: 40
            radius: Tokens.radiusSmall
            color: Tokens.surfaceRaised

            Image {
              id: preview
              anchors.fill: parent
              anchors.margins: 2
              fillMode: Image.PreserveAspectCrop
              source: root.paths.length === 1 ? "file://" + root.paths[0] : ""
              visible: status === Image.Ready
            }
            Text {
              anchors.centerIn: parent
              visible: !preview.visible
              text: "󰒖"
              color: Tokens.foreground
              font.family: Tokens.fontFamily
              font.pixelSize: Tokens.iconSize
            }
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter

            Text {
              text: root.paths.length === 1
                ? String(root.paths[0]).split("/").pop()
                : root.paths.length + " files"
              color: Tokens.foreground
              font.family: Tokens.fontFamily
              font.pixelSize: Tokens.fontSize
              font.bold: true
            }
            Text {
              visible: root.paths.length === 0
              text: "Nothing to share"
              color: Tokens.muted
              font.family: Tokens.fontFamily
              font.pixelSize: Tokens.fontSizeSmall
            }
          }
        }

        Text {
          visible: root.loading
          text: "Looking for devices…"
          color: Tokens.muted
          font.family: Tokens.fontFamily
          font.pixelSize: Tokens.fontSize
        }

        Text {
          visible: !root.loading && root.targets.length === 0
          text: "No devices found — open LocalSend on your phone"
          color: Tokens.muted
          font.family: Tokens.fontFamily
          font.pixelSize: Tokens.fontSize
          wrapMode: Text.Wrap
          width: sheet.width - Tokens.padding * 2
        }

        Grid {
          id: grid
          columns: 2
          spacing: Tokens.spacing
          visible: root.targets.length > 0
          width: sheet.width - Tokens.padding * 2

          Repeater {
            model: root.targets

            Rectangle {
              id: target

              required property var modelData
              required property int index

              width: (grid.width - Tokens.spacing) / 2
              height: 48
              radius: Tokens.radius
              color: root.selectedIndex === target.index
                ? Tokens.surfaceRaised
                : (area.containsMouse ? Tokens.surfaceRaised : Tokens.surface)
              border.color: root.selectedIndex === target.index ? Tokens.accent : Tokens.border
              border.width: 1

              Rectangle {
                id: badge
                anchors.left: parent.left
                anchors.leftMargin: Tokens.spacing
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                radius: width / 2
                color: Tokens.stateColor("on")

                Text {
                  anchors.centerIn: parent
                  text: root.kindGlyph(target.modelData.kind)
                  color: Tokens.background
                  font.family: Tokens.fontFamily
                  font.pixelSize: Tokens.iconSize - 2
                }
              }

              Text {
                anchors.left: badge.right
                anchors.leftMargin: Tokens.spacing
                anchors.right: parent.right
                anchors.rightMargin: Tokens.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: target.modelData.label
                elide: Text.ElideRight
                color: Tokens.foreground
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontSize
              }

              MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.selectedIndex = target.index
                  root.send(target.modelData)
                }
              }
            }
          }
        }

        Text {
          text: "Enter send · R refresh · Esc close"
          color: Tokens.muted
          font.family: Tokens.fontFamily
          font.pixelSize: Tokens.fontSizeSmall
        }
      }
    }
  }
}
