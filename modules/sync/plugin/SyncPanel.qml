pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Delight"

// Pairing sheet for `delight sync pair`: this device's Syncthing ID as a QR
// code, pending incoming device requests (Accept / Ignore), and "Add device
// by ID". The payload is `delight sync pair --json`; it is re-read while open.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property string deviceId: ""
  property string qr: ""
  property var pending: []
  property var devices: []
  property string message: ""
  property bool messageIsError: false

  function open(payloadJson) {
    apply(payloadJson)
    opened = true
    refresh()
  }

  function close() {
    opened = false
    message = ""
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("delight.sync")
    else close()
  }

  function apply(text) {
    let data = null
    try {
      data = JSON.parse(text || "{}")
    } catch (e) {
      console.warn("delight.sync: bad pair JSON", e)
      return
    }
    if (!data || typeof data !== "object") return
    if (typeof data.deviceId === "string") deviceId = data.deviceId
    qr = typeof data.qr === "string" ? data.qr : ""
    pending = Array.isArray(data.pending) ? data.pending : []
    devices = Array.isArray(data.devices) ? data.devices : []
  }

  function refresh() {
    if (!reader.running) reader.running = true
  }

  function act(args, done) {
    if (action.running) return
    message = ""
    action.doneText = done
    action.command = ["delight", "sync"].concat(args)
    action.running = true
  }

  function shortId(id) {
    return (id || "").split("-").slice(0, 2).join("-")
  }

  Process {
    id: reader
    command: ["delight", "sync", "pair", "--json"]
    stdout: StdioCollector {
      onStreamFinished: root.apply(this.text)
    }
  }

  Process {
    id: action
    property string doneText: ""
    stderr: StdioCollector {
      id: actionErr
    }
    onExited: function(code) {
      root.messageIsError = code !== 0
      root.message = code === 0 ? doneText : (actionErr.text.trim() || "Something went wrong")
      if (code === 0) idInput.text = ""
      root.refresh()
    }
  }

  Timer {
    interval: 3000
    repeat: true
    running: root.opened
    onTriggered: root.refresh()
  }

  component Pill: Rectangle {
    id: pill
    property string label: ""
    property bool primary: false
    signal clicked()
    implicitWidth: pillText.implicitWidth + Tokens.padding * 2
    implicitHeight: pillText.implicitHeight + Tokens.spacing
    radius: height / 2
    color: primary ? Tokens.accent : (pillMouse.containsMouse ? Tokens.surfaceRaised : Tokens.surface)
    opacity: enabled ? 1 : 0.5
    border.color: Tokens.border
    border.width: primary ? 0 : 1

    Behavior on color {
      ColorAnimation { duration: Tokens.animationFast }
    }

    Text {
      id: pillText
      anchors.centerIn: parent
      text: pill.label
      color: pill.primary ? Tokens.background : Tokens.foreground
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSizeSmall
      font.bold: pill.primary
    }

    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.clicked()
    }
  }

  component Caption: Text {
    color: Tokens.muted
    font.family: Tokens.fontFamily
    font.pixelSize: Tokens.fontSizeSmall
    wrapMode: Text.Wrap
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
    WlrLayershell.namespace: "delight-sync"

    implicitWidth: sheet.implicitWidth
    implicitHeight: sheet.implicitHeight

    Sheet {
      id: sheet
      anchors.fill: parent
      implicitWidth: 420
      title: "Pair a device"
      focus: true
      Keys.onEscapePressed: root.requestClose()

      Row {
        width: parent.width
        spacing: Tokens.padding

        Rectangle {
          width: 148
          height: 148
          radius: Tokens.radiusSmall
          color: "white"

          Image {
            anchors.fill: parent
            anchors.margins: 6
            source: root.qr !== "" ? "file://" + root.qr : ""
            cache: false
            smooth: false
            fillMode: Image.PreserveAspectFit
            visible: root.qr !== ""
          }

          Text {
            anchors.centerIn: parent
            width: parent.width - Tokens.padding * 2
            visible: root.qr === ""
            text: "Install qrencode to show a QR code"
            color: "black"
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSizeSmall
          }
        }

        Column {
          width: parent.width - 148 - Tokens.padding
          spacing: Tokens.spacing

          Text {
            width: parent.width
            text: "Scan with Syncthing on your phone, or enter this ID on another computer."
            color: Tokens.foreground
            wrapMode: Text.Wrap
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSize
          }

          TextEdit {
            width: parent.width
            text: root.deviceId || "Waiting for Syncthing…"
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            color: Tokens.muted
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSizeSmall
          }

          Pill {
            label: "Copy ID"
            enabled: root.deviceId !== ""
            onClicked: Quickshell.execDetached(["wl-copy", root.deviceId])
          }
        }
      }

      Caption {
        width: parent.width
        visible: root.pending.length > 0
        text: root.pending.length === 1 ? "1 device wants to sync" : root.pending.length + " devices want to sync"
      }

      Repeater {
        model: root.pending

        Rectangle {
          id: request
          required property var modelData
          width: sheet.width - Tokens.padding * 2
          implicitHeight: requestRow.implicitHeight + Tokens.spacing * 2
          radius: Tokens.radiusSmall
          color: Tokens.surface

          Row {
            id: requestRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Tokens.spacing
            spacing: Tokens.spacing

            Column {
              width: parent.width - acceptPill.width - ignorePill.width - Tokens.spacing * 2

              Text {
                width: parent.width
                text: request.modelData.name || root.shortId(request.modelData.id)
                elide: Text.ElideRight
                color: Tokens.foreground
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontSize
              }

              Caption {
                width: parent.width
                text: root.shortId(request.modelData.id) + (request.modelData.address ? " · " + request.modelData.address : "")
                elide: Text.ElideRight
              }
            }

            Pill {
              id: acceptPill
              anchors.verticalCenter: parent.verticalCenter
              label: "Accept"
              primary: true
              onClicked: root.act(["accept", request.modelData.id], "Accepted " + (request.modelData.name || root.shortId(request.modelData.id)))
            }

            Pill {
              id: ignorePill
              anchors.verticalCenter: parent.verticalCenter
              label: "Ignore"
              onClicked: root.act(["ignore", request.modelData.id], "Ignored " + root.shortId(request.modelData.id))
            }
          }
        }
      }

      Caption {
        width: parent.width
        text: "Add device by ID"
      }

      Row {
        width: parent.width
        spacing: Tokens.spacing

        Rectangle {
          width: parent.width - addPill.width - Tokens.spacing
          height: addPill.height + Tokens.spacing
          radius: Tokens.radiusSmall
          color: Tokens.surface
          border.color: idInput.activeFocus ? Tokens.accent : Tokens.border
          border.width: 1

          TextInput {
            id: idInput
            anchors.fill: parent
            anchors.margins: Tokens.spacing
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: Tokens.foreground
            selectByMouse: true
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSizeSmall
            onAccepted: addPill.clicked()

            Caption {
              anchors.verticalCenter: parent.verticalCenter
              visible: idInput.text === ""
              text: "XXXXXXX-XXXXXXX-…"
            }
          }
        }

        Pill {
          id: addPill
          anchors.verticalCenter: parent.verticalCenter
          label: "Add"
          enabled: idInput.text.trim() !== ""
          onClicked: root.act(["add-device", idInput.text.trim()], "Device added")
        }
      }

      Caption {
        width: parent.width
        visible: root.devices.length > 0
        text: "Paired: " + root.devices.map(function(d) { return d.name + (d.connected ? " ●" : " ○") }).join("   ")
      }

      Text {
        width: parent.width
        visible: root.message !== ""
        text: root.message
        wrapMode: Text.Wrap
        color: root.messageIsError ? Tokens.urgent : Tokens.accent
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSizeSmall
      }

      Row {
        spacing: Tokens.spacing

        Pill {
          label: "Done"
          onClicked: root.requestClose()
        }

        Pill {
          label: "Open Syncthing"
          onClicked: Quickshell.execDetached(["delight", "sync", "open"])
        }
      }
    }
  }
}
