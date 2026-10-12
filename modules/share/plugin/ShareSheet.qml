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
  property string delightBin: "delight"
  property var targetsCommand: []
  property var targets: []
  property bool loading: false
  property int selectedIndex: 0

  readonly property string pluginId: (manifest && manifest.id) || "delight.share"

  function open(payloadJson) {
    try {
      const payload = JSON.parse(payloadJson || "{}")
      root.paths = Array.isArray(payload.paths) ? payload.paths : []
      if (typeof payload.delightBin === "string" && payload.delightBin.length > 0)
        root.delightBin = payload.delightBin
      root.targetsCommand = Array.isArray(payload.targetsCommand) && payload.targetsCommand.length > 0
        ? payload.targetsCommand
        : [root.delightBin, "share-targets", "--json"]
    } catch (e) {
      root.paths = []
      root.targetsCommand = [root.delightBin, "share-targets", "--json"]
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

  function baseName(path) {
    return String(path).split("/").pop()
  }

  function isImage(path) {
    return /\.(png|jpe?g|gif|webp|bmp|svg)$/i.test(String(path))
  }

  function transportLabel(target) {
    const id = String(target.id || "")
    if (id.indexOf("airdrop:") === 0)
      return "AirDrop"
    if (id.indexOf("localsend:") === 0)
      return "LocalSend"
    return target.module || ""
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
    const module = (typeof target.module === "string" && target.module.length > 0) ? target.module : "share"
    const argv = [root.delightBin, module, "send", target.id].concat(root.paths)
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

        implicitWidth: 480

        Row {
          spacing: Tokens.padding

          Rectangle {
            width: 56
            height: 56
            radius: Tokens.radiusSmall
            color: Tokens.surfaceRaised
            clip: true

            Image {
              id: preview
              anchors.fill: parent
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              sourceSize.width: 112
              sourceSize.height: 112
              source: root.paths.length === 1 && root.isImage(root.paths[0]) ? "file://" + root.paths[0] : ""
              visible: status === Image.Ready
            }
            Text {
              anchors.centerIn: parent
              visible: !preview.visible
              text: root.paths.length > 1 ? "󰉋" : "󰈙"
              color: Tokens.foreground
              font.family: Tokens.fontFamily
              font.pixelSize: Tokens.iconSize * 1.6
            }
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            width: sheet.width - Tokens.padding * 3 - 56

            Text {
              width: parent.width
              elide: Text.ElideMiddle
              text: root.paths.length === 0
                ? "Nothing to share"
                : root.paths.length === 1 ? root.baseName(root.paths[0]) : root.paths.length + " items"
              color: Tokens.foreground
              font.family: Tokens.fontFamily
              font.pixelSize: Tokens.fontSize + 1
              font.bold: true
            }
            Text {
              width: parent.width
              elide: Text.ElideMiddle
              visible: root.paths.length > 0
              text: root.paths.length === 1
                ? String(root.paths[0]).split("/").slice(0, -1).join("/")
                : root.paths.map(root.baseName).join(", ")
              color: Tokens.muted
              font.family: Tokens.fontFamily
              font.pixelSize: Tokens.fontSizeSmall
            }
          }
        }

        Rectangle {
          width: sheet.width - Tokens.padding * 2
          height: 1
          color: Tokens.border
        }

        Text {
          visible: root.loading && root.targets.length === 0
          text: "Looking for devices…"
          color: Tokens.muted
          font.family: Tokens.fontFamily
          font.pixelSize: Tokens.fontSize
        }

        Text {
          visible: !root.loading && root.targets.length === 0
          text: "No devices found. Open LocalSend on your phone and press R."
          color: Tokens.muted
          font.family: Tokens.fontFamily
          font.pixelSize: Tokens.fontSize
          wrapMode: Text.Wrap
          width: sheet.width - Tokens.padding * 2
        }

        Grid {
          id: grid
          columns: 4
          columnSpacing: Tokens.spacing
          rowSpacing: Tokens.spacing
          visible: root.targets.length > 0
          width: sheet.width - Tokens.padding * 2

          Repeater {
            model: root.targets

            Rectangle {
              id: target

              required property var modelData
              required property int index
              readonly property bool selected: root.selectedIndex === target.index

              width: (grid.width - Tokens.spacing * (grid.columns - 1)) / grid.columns
              height: 104
              radius: Tokens.radius
              color: target.selected || area.containsMouse ? Tokens.surface : "transparent"

              Rectangle {
                id: badge
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Tokens.spacing
                width: 52
                height: 52
                radius: width / 2
                color: target.selected ? Tokens.accent : Tokens.surfaceRaised
                border.color: target.selected ? Tokens.accent : Tokens.border
                border.width: 1

                Behavior on color {
                  ColorAnimation { duration: Tokens.animationFast }
                }

                Text {
                  anchors.centerIn: parent
                  text: root.kindGlyph(target.modelData.kind)
                  color: target.selected ? Tokens.background : Tokens.foreground
                  font.family: Tokens.fontFamily
                  font.pixelSize: Tokens.iconSize + 6
                }
              }

              Column {
                anchors.top: badge.bottom
                anchors.topMargin: 6
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                spacing: 1

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: target.modelData.label
                  elide: Text.ElideRight
                  color: Tokens.foreground
                  font.family: Tokens.fontFamily
                  font.pixelSize: Tokens.fontSizeSmall + 1
                  font.bold: target.selected
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: root.transportLabel(target.modelData)
                  elide: Text.ElideRight
                  color: Tokens.muted
                  font.family: Tokens.fontFamily
                  font.pixelSize: Tokens.fontSizeSmall - 1
                }
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
